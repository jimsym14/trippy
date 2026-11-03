"""Versioned editorial dataset integration; no inference, live fetch or publication."""
import argparse
from collections import Counter
from contextlib import closing
from copy import deepcopy
import json
import os
from pathlib import Path
import sqlite3
import tempfile

from trippy.sources.curation_cycle import load_pack
from trippy.sources.extraction import fingerprint
from trippy.sources.followup_materialize import materialize as apply_sources
from trippy.sources.unattended import immutable_write


def integrate(pack, held, prepared, handoff, cues, audit, annotation_layer, identity_links, operational, target=95):
    if not 0<=target<=100:raise ValueError('Editorial target must be a percentage')
    entry_keys=[e['key'] for c in prepared['chunks'] for e in c['payload']['entries']]
    decisions=[d['key'] for d in audit['decisions']]
    if len(set(entry_keys))!=len(entry_keys) or sorted(decisions)!=sorted(entry_keys):
        raise ValueError('Every prepared source slot needs exactly one manual disposition')
    if len({h['key'] for h in held})!=len(held):
        raise ValueError('Duplicate held source claims')
    pending=[h for h in held if h['key'] in set(entry_keys)]
    preserved=[deepcopy(h) for h in held if h['key'] not in set(entry_keys)]
    result=apply_sources(pack,pending,prepared,handoff,cues,audit)
    final=deepcopy(result['normalized']);final_held=result['held_claims']+preserved
    before_active=sum(len(r['claims']) for r in pack['drafts'])
    before=before_active+len(held)
    after_active=sum(len(r['claims']) for r in final['drafts'])
    if before!=after_active+len(final_held):
        raise ValueError('Source integration must conserve all original slots')
    originals={r['upstream_occurrence_id']:r for r in pack['drafts']}
    for record in final['drafts']:
        old=originals[record['upstream_occurrence_id']]
        if record['claims'][:len(old['claims'])]!=old['claims'] or record['claim_review_metadata'][:len(old['claim_review_metadata'])]!=old['claim_review_metadata']:
            raise ValueError('Existing editorial decisions must remain unchanged')
    direct=final['previous_to_normalized_ids']
    older=pack.get('previous_to_normalized_ids',{})
    final['previous_to_normalized_ids']={**direct,**{old:direct[base] for old,base in older.items()}}
    records={r['id']:r for r in final['drafts']}
    def bind(old_id,ids):
        new_id=final['previous_to_normalized_ids'].get(old_id,old_id)
        row=records.get(new_id)
        return new_id if row else None, bool(row and set(ids)<={fingerprint(c) for c in row['claims']})
    annotations=[];seen=set()
    for original in annotation_layer['annotations']:
        item=deepcopy(original);entry=item['original_entry'];decision=item['manual_decision']
        if item['key'] in seen:raise ValueError('Duplicate annotation slot')
        seen.add(item['key'])
        if item['source_entry_sha256']!=fingerprint(entry):raise ValueError('Stale annotation source entry')
        ids=decision['evidence_claim_ids'] if decision else entry['proposal']['claim_ids']
        current,bound=bind(entry['record_id'],ids)
        item.update(current_record_id=current,claim_binding_current=bound)
        # Carry forward actual manual eligibility, never promote AI-only items.
        item['source_discovery_eligible']=bool(original['source_discovery_eligible'] and bound and decision)
        item.update(canonical_identity_verified=False,current_trip_verified=False,planner_fact_eligible=False)
        annotations.append(item)
    prior_reviews=[]
    for review in annotation_layer.get('preserved_manual_reviews',[]):
        copy=deepcopy(review);current,bound=bind(copy['record_id'],copy['facet']['claim_ids'])
        copy.update(current_record_id=current,claim_binding_current=bound,
            source_discovery_eligible=bool(review.get('source_discovery_eligible') and bound),
            canonical_identity_verified=False,current_trip_verified=False,planner_fact_eligible=False)
        prior_reviews.append(copy)
    manual_count=sum(a['manual_decision'] is not None for a in annotations)
    manual_stale=sum(bool(a['manual_decision']) and not a['claim_binding_current'] for a in annotations)
    if manual_stale:raise ValueError('Manually approved annotations require fresh comparison after source edits')
    if any(p.get('current_trip_verified') for name in ('structured_fields','prose_proposals') for p in operational.get(name,[])):
        raise ValueError('This source-only integration cannot certify trip-date provider facts')
    if any(e['status']!='source_identity_link_reviewed_coordinate_and_fields_pending' for e in identity_links.get('events',[])):
        raise ValueError('This integration accepts only reviewed source/catalog correspondences')
    readiness={
        'metric':'active_editorial_source_claims_divided_by_all_conserved_source_claims',
        'definition':'Editorial retention/admission coverage, not truth accuracy, video completeness or planner readiness.',
        'before_active':before_active,'before_held':len(held),'source_slots':before,
        'before_percent':round(100*before_active/before,2) if before else 0,
        'target_percent':target,'after_active':after_active,'after_held':len(final_held),
        'after_percent':round(100*after_active/before,2) if before else 0,
        'target_met':bool(before and 100*after_active/before>=target),
        'manual_source_decisions_this_pass':len(decisions),
        'annotation_slots':len(annotations),'manual_annotation_reviews':manual_count,
        'previous_manual_annotation_reviews':len(prior_reviews),
        'manual_annotation_review_coverage_percent':round(100*(manual_count+len(prior_reviews))/(len(annotations)+len(prior_reviews)),2) if annotations else 0,
        'annotation_review_pending':len(annotations)-manual_count,
        'source_catalog_correspondences':len(identity_links.get('events',[])),
        'approved_canonical_places':0,'trip_verified_fields':0,'complete_itineraries_verified':0,
        'planner_ready':False,'ready_to_publish':False}
    manifest={'version':1,'source_integration_manifest':result['manifest'],
        'source_pack_sha256':fingerprint(final),'held_sha256':fingerprint(final_held),
        'annotation_layer_sha256':fingerprint(annotation_layer), 'identity_links_sha256':fingerprint(identity_links),
        'operational_sha256':fingerprint(operational),'engine_sha256':fingerprint(Path(__file__).read_text()),
        'target_percent':target}
    return {'manifest':manifest,'normalized':final,'held_claims':final_held,
        'source_editorial_events':result['editorial_events'],'source_review_actions':result['summary']['actions'],
        'annotations':annotations,'preserved_manual_reviews':prior_reviews,
        'identity_links':deepcopy(identity_links),'operational':deepcopy(operational),
        'readiness':readiness,'ready_to_publish':False}


def snapshot_rows(bundle):
    rows={name:[] for name in ('records','claims','held_claims','annotations','prior_manual_reviews','identity_links','operational_fields')}
    for r in bundle['normalized']['drafts']:
        rows['records'].append((r['id'],json.dumps(r,ensure_ascii=False,sort_keys=True)))
        if len(r['claims'])!=len(r['claim_review_metadata']):raise ValueError('One source occurrence per claim metadata slot required')
        for ordinal,(claim,metadata) in enumerate(zip(r['claims'],r['claim_review_metadata'])):
            if metadata['claim_sha256']!=fingerprint(claim):raise ValueError('Stale source metadata binding')
            rows['claims'].append((metadata['upstream_key'],r['id'],ordinal,fingerprint(claim),
                json.dumps(claim,ensure_ascii=False,sort_keys=True),json.dumps(metadata,ensure_ascii=False,sort_keys=True)))
    rows['held_claims']=[(h['key'],json.dumps(h,ensure_ascii=False,sort_keys=True)) for h in bundle['held_claims']]
    rows['annotations']=[(a['key'],a['current_record_id'],a['status'],int(a['source_discovery_eligible']),
        json.dumps(a,ensure_ascii=False,sort_keys=True)) for a in bundle['annotations']]
    rows['prior_manual_reviews']=[(str(i),json.dumps(r,ensure_ascii=False,sort_keys=True)) for i,r in enumerate(bundle['preserved_manual_reviews'])]
    rows['identity_links']=[(str(i),json.dumps(e,ensure_ascii=False,sort_keys=True)) for i,e in enumerate(bundle['identity_links'].get('events',[]))]
    rows['operational_fields']=[(kind,str(i),json.dumps(e,ensure_ascii=False,sort_keys=True))
        for kind in ('structured_fields','prose_proposals') for i,e in enumerate(bundle['operational'].get(kind,[]))]
    return rows


def verify_snapshot(path,bundle):
    expected=snapshot_rows(bundle)
    with closing(sqlite3.connect(Path(path).resolve().as_uri()+'?mode=ro',uri=True)) as db:
        if db.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise ValueError('Snapshot integrity failure')
        if db.execute('PRAGMA foreign_key_check').fetchall():raise ValueError('Snapshot foreign key failure')
        for table,rows in expected.items():
            actual=db.execute('SELECT * FROM '+table).fetchall()
            if sorted(actual,key=str)!=sorted(rows,key=str):raise ValueError('Snapshot content differs: '+table)
        if db.execute('SELECT bundle_sha256 FROM edition').fetchone()[0]!=fingerprint(bundle):raise ValueError('Snapshot edition differs')


def write_snapshot(path,bundle):
    path=Path(path)
    if path.exists():verify_snapshot(path,bundle);return
    descriptor,name=tempfile.mkstemp(prefix=path.name+'.',suffix='.building',dir=path.parent)
    os.close(descriptor);temporary=Path(name)
    rows=snapshot_rows(bundle)
    try:
        with closing(sqlite3.connect(temporary)) as db:
            db.execute('PRAGMA foreign_keys=ON')
            db.executescript('''CREATE TABLE edition(bundle_sha256 TEXT PRIMARY KEY,ready_to_publish INTEGER CHECK(ready_to_publish=0));
                CREATE TABLE records(id TEXT PRIMARY KEY,document TEXT NOT NULL);
                CREATE TABLE claims(upstream_key TEXT PRIMARY KEY,record_id TEXT REFERENCES records(id),ordinal INTEGER,content_sha256 TEXT,document TEXT,metadata TEXT);
                CREATE TABLE held_claims(upstream_key TEXT PRIMARY KEY,document TEXT NOT NULL);
                CREATE TABLE annotations(key TEXT PRIMARY KEY,record_id TEXT REFERENCES records(id),status TEXT,source_discovery_eligible INTEGER,document TEXT);
                CREATE TABLE prior_manual_reviews(key TEXT PRIMARY KEY,document TEXT NOT NULL);
                CREATE TABLE identity_links(key TEXT PRIMARY KEY,document TEXT NOT NULL);
                CREATE TABLE operational_fields(kind TEXT,key TEXT,document TEXT,PRIMARY KEY(kind,key));
                CREATE INDEX claims_by_record ON claims(record_id);
                CREATE INDEX annotations_by_scope ON annotations(source_discovery_eligible,status,record_id);''')
            db.execute('INSERT INTO edition VALUES (?,0)',(fingerprint(bundle),))
            for table,values in rows.items():
                if values:db.executemany('INSERT INTO '+table+' VALUES ('+','.join('?' for _ in values[0])+')',values)
            db.commit()
        verify_snapshot(temporary,bundle)
        try:os.link(temporary,path)
        except FileExistsError:verify_snapshot(path,bundle)
        temporary.unlink()
    except Exception:
        if temporary.exists():temporary.unlink()
        raise


def build(recipe):
    read=lambda path:json.loads(Path(path).read_text())
    source=read(recipe['source_recipe'])
    _,cues,receipts=load_pack(read(source['inputs'])['inputs'],read(source['original']))
    result=integrate(read(recipe['pack']),read(recipe['held']),read(recipe['prepared']),
        read(recipe['handoff']),cues,read(recipe['source_audit']),read(recipe['annotations']),
        read(recipe['identity_links']),read(recipe['operational']),recipe.get('source_editorial_target_percent',95))
    result['manifest']['original_evidence_inputs']=receipts
    folder=Path(recipe['output_root'])/fingerprint(result['manifest'])[:16]
    for name,value in [('dataset.json',result),('normalized.json',result['normalized']),
        ('held-claims.json',result['held_claims']),('readiness.json',result['readiness'])]:
        immutable_write(folder/name,value)
    write_snapshot(folder/'dataset.sqlite',result)
    return folder,result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe',type=Path,required=True)
    args=parser.parse_args();folder,result=build(json.loads(args.recipe.read_text()))
    print(json.dumps({'folder':str(folder),'source_review_actions':result['source_review_actions'],
        'readiness':result['readiness'],'paid_calls':0,'http_requests':0},indent=2))


if __name__=='__main__':main()
