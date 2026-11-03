"""Measured private curation cycles; source evidence is never rewritten."""
import argparse
from collections import Counter, defaultdict
from contextlib import closing
from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sqlite3

from trippy.catalog.normalize import normalize_text
from .coverage import MENTION_FIELDS, private_write
from .extraction import Citation, Claim, fingerprint, validate_result

VERSION=1


def load_pack(inputs, original):
    cues={}
    for chunk in original['chunks']:
        for cue in chunk['payload']['segments']:
            previous=cues.get(cue['segment_id'])
            if previous and previous!=cue:raise ValueError('Conflicting original source cue')
            cues[cue['segment_id']]=cue
    records=[];receipts=[];seen=set()
    for name in inputs:
        path=Path(name);document=json.loads(path.read_text())
        receipts.append({'path':str(path),'sha256':fingerprint(document)})
        for cue in document.get('source_evidence_inventory',[]):
            original_cue=cues.get(cue['segment_id'])
            stripped={k:v for k,v in cue.items() if k!='additional_audit_selected'}
            if original_cue and original_cue!=stripped:raise ValueError('Result inventory differs from original evidence')
            cues[cue['segment_id']]=stripped
        for record in document['drafts']:
            if record['id'] in seen:raise ValueError('Duplicate input occurrence; select replacement versions instead of appending')
            seen.add(record['id']);records.append(deepcopy(record))
    validate_pack(records,cues)
    return records,cues,receipts


def validate_pack(records,cues):
    for record in records:
        source_id=record['source']['external_id']
        evidence=[s for s in cues.values() if s['segment_id'].rsplit(':',1)[0]==source_id]
        validate_result({'payload':{'segments':evidence}},
            {'mentions':[{k:record[k] for k in MENTION_FIELDS}]})


def apply_decisions(records,decisions,cues):
    updated={r['id']:deepcopy(r) for r in records};events=[]
    for decision in decisions:
        if decision.get('review_method')!='agent_source_comparison' or not decision.get('reason'):
            raise ValueError('Decision requires explicit source comparison and reason')
        record=updated.get(decision['occurrence_id'])
        if record is None:raise ValueError('Decision references missing occurrence')
        before=deepcopy(record)
        if decision['action'] in {'claim_dimension','claim_split','claim_citations_add','claim_value'}:
            matches=[c for c in record['claims'] if fingerprint(c)==decision['claim_sha256']]
            if len(matches)!=1:raise ValueError('Decision references stale/ambiguous claim')
            if decision['action']=='claim_dimension':
                candidate={**matches[0],'dimension':decision['dimension']}
                Claim.model_validate(candidate)
                matches[0]['dimension']=decision['dimension']
            elif decision['action']=='claim_value':
                candidate={**matches[0],'value':decision['value']}
                Claim.model_validate(candidate)
                matches[0]['value']=decision['value']
            elif decision['action']=='claim_citations_add':
                additions=[Citation.model_validate(q).model_dump() for q in decision['additional_citations']]
                if not additions:raise ValueError('Citation addition must provide source evidence')
                for citation in additions:
                    if fingerprint(citation) in {fingerprint(q) for q in matches[0]['citations']}:
                        raise ValueError('Citation already exists')
                    cue=cues.get(citation['segment_id'])
                    if cue is None or citation['segment_id'].rsplit(':',1)[0]!=record['source']['external_id']:
                        raise ValueError('Citation must belong to original source')
                    matches[0]['citations'].append(citation)
            else:
                original_claim=matches[0];allowed={fingerprint(q) for q in original_claim['citations']}
                replacements=[Claim.model_validate(c).model_dump() for c in decision['claims']]
                if len(replacements)<2:raise ValueError('Split requires at least two claims')
                if any(fingerprint(q) not in allowed for c in replacements for q in c['citations']):
                    raise ValueError('Split cannot add or rewrite source quotations')
                position=record['claims'].index(original_claim)
                record['claims'][position:position+1]=replacements
        elif decision['action']=='category_remove':
            if decision['category'] not in record['categories']:raise ValueError('Category decision is stale')
            record['categories'].remove(decision['category'])
            if not record['categories']:
                if decision.get('fallback_category')!='other':
                    raise ValueError('Removing the last category requires an explicit generic fallback')
                record['categories']=['other']
        else:raise ValueError('Unsupported correction; cannot alter names or original source quotations')
        events.append({'decision':decision,'before_sha256':fingerprint(before),
            'after_sha256':fingerprint(record),'original':before,'corrected':deepcopy(record),
            'approval_scope':'Explicit source-compared editorial correction; not independent fact or canonical identity approval'})
    output=[];mapping={}
    for old_id,record in updated.items():
        new_id=fingerprint({'source_occurrence':old_id,'source':record['source']['external_id'],
            'mention':{k:record[k] for k in MENTION_FIELDS}})
        mapping[old_id]=new_id;record['id']=new_id;record['upstream_occurrence_id']=old_id
        output.append(record)
    validate_pack(output,cues)
    return output,events,mapping


def metrics(records):
    dimensions=Counter(c['dimension'] for r in records for c in r['claims'])
    venues=[r for r in records if r['kind']=='venue']
    return {'records':len(records),'claims':sum(len(r['claims']) for r in records),
        'source_videos':len({r['source']['external_id'] for r in records}),
        'publisher_groups':len({r['publisher_group'] for r in records}),
        'venue_occurrences':len(venues),'identity_uncertain_records':sum(r['identity_uncertain'] for r in records),
        'normalized_venue_name_groups_not_canonical':len({normalize_text(r['name']) for r in venues}),
        'identity_candidate_records_not_approved':sum(bool(r.get('identity_candidates')) for r in records),
        'claim_dimensions':dict(dimensions),'record_categories':dict(Counter(c for r in records for c in r['categories']))}


def has_term(text,terms):
    return any(re.search(r'(?<!\w)'+re.escape(normalize_text(term))+r'(?!\w)',normalize_text(text)) for term in terms)


def measure_coverage(records,profile,observations):
    cells=[]
    for cell in profile['coverage_cells']:
        candidates=[]
        for record in records:
            if record['kind'] not in cell.get('kinds',['venue']):continue
            matches=[fingerprint(c) for c in record['claims']
                if c['dimension'] in cell.get('dimensions',[]) and
                (not cell.get('terms') or has_term(c['value'],cell['terms']))]
            if matches:candidates.append({'occurrence_id':record['id'],'name':record['name'],
                'claim_ids':matches,'identity_uncertain':record['identity_uncertain']})
        web=[o['id'] for o in observations if cell['id'] in o.get('coverage_cells',[])]
        cells.append({'id':cell['id'],'scope':cell['scope'],'transcript_candidates':candidates,
            'reviewed_external_observation_ids':web,
            'canonical_verified_options':0,
            'state':'candidates_require_identity_and_field_review' if candidates or web else 'no_candidate_detected',
            'reason':'No canonical release or current trip-constraint verification is approved',
            'query_variants':cell['queries']})
    return cells


def validate_observations(observations):
    seen=set()
    for observation in observations:
        if observation['id'] in seen:raise ValueError('Duplicate external observation ID')
        seen.add(observation['id'])
        if not observation.get('source_url','').startswith('https://') or not observation.get('retrieved_at'):
            raise ValueError('External observation needs an HTTPS source and retrieval time')
        if observation.get('review_method')!='agent_primary_page_comparison':
            raise ValueError('Observation needs primary-page review provenance')
        if observation.get('current_trip_verified') is not False:
            raise ValueError('This curation stage cannot approve exact trip availability')
        if observation.get('allergy_safe') is not None:
            raise ValueError('No blanket allergy safety assertion is permitted')
        if observation.get('rating') is not None:
            raise ValueError('No rating without a dedicated verified rating path')


def run_cycle(city_id,records,cues,receipts,decisions,profile,observations,root):
    validate_observations(observations)
    if profile['city_id']!=city_id:raise ValueError('Coverage profile belongs to another city')
    spec={'version':VERSION,'engine_sha256':fingerprint(Path(__file__).read_text()),
        'city_id':city_id,'inputs':receipts,'decisions':decisions,
        'profile':profile,'external_observations':observations}
    run_id=fingerprint(spec);folder=Path(root)/city_id/run_id[:16]
    corrected,events,mapping=apply_decisions(records,decisions,cues)
    before=metrics(records);after=metrics(corrected)
    groups=defaultdict(list)
    for record in corrected:
        key=(normalize_text(record['name']),record['kind'],normalize_text(record['branch'] or ''))
        groups[key].append(record['id'])
    proposals=[{'name_key':k[0],'kind':k[1],'branch_key':k[2],'occurrence_ids':ids,
        'status':'possible_duplicate_not_merged'} for k,ids in groups.items() if len(ids)>1]
    coverage=measure_coverage(corrected,profile,observations)
    summary={'run_id':run_id,'city_id':city_id,'before':before,'after':after,
        'editorial_corrections':len(events),'external_observations':len(observations),
        'source_evidence_revalidated':True,'model_api_calls':0,'catalog_writes':0,
        'coverage_cells':len(coverage),'cells_without_detected_candidates':sum(c['state']=='no_candidate_detected' for c in coverage),
        'measurement_limitations':'Candidate and lexical diagnostics are not proven coverage or absence; semantic, language and identity review remain required',
        'ready_to_publish':False,'ready_for_complete_planner':False,
        'remaining_gates':['canonical_identity','quarantine_review','supported_semantic_fit',
            'coverage_depth_diversity','selected_trip_current_facts','planner_scenario_evaluation'],
        'repeat_behavior':'Same input/decision/evidence hashes replay without new processing or spend'}
    documents={'manifest.json':spec,'normalized.json':{'drafts':corrected,
        'upstream_to_normalized_ids':mapping,'upstream_receipts':receipts,
        'prior_review_lineage':'Preserved in immutable upstream files; translate references using mapping',
        'status':'private_corrected_source_pack_not_canonical','ready_to_publish':False},
        'changes.json':events,'coverage.json':coverage,'identity-proposals.json':proposals,
        'external-observations.json':observations,'summary.json':summary}
    for name,document in documents.items():
        path=folder/name
        if path.exists():
            if json.loads(path.read_text())!=document:raise ValueError('Existing cycle artifact differs')
        else:private_write(path,document)
    ledger=Path(root)/city_id/'curation.sqlite'
    with closing(sqlite3.connect(ledger)) as db,db:
        db.execute('CREATE TABLE IF NOT EXISTS curation_runs(run_id TEXT PRIMARY KEY,created_at TEXT,summary_json TEXT)')
        db.execute('CREATE TABLE IF NOT EXISTS curation_events(run_id TEXT,event_number INTEGER,event_json TEXT,PRIMARY KEY(run_id,event_number))')
        db.execute('CREATE TABLE IF NOT EXISTS curation_observations(run_id TEXT,observation_id TEXT,observation_json TEXT,PRIMARY KEY(run_id,observation_id))')
        db.execute('INSERT OR IGNORE INTO curation_runs VALUES(?,?,?)',
            (run_id,datetime.now(timezone.utc).isoformat(),json.dumps(summary)))
        db.executemany('INSERT OR IGNORE INTO curation_events VALUES(?,?,?)',
            [(run_id,i,json.dumps(event,ensure_ascii=False)) for i,event in enumerate(events)])
        db.executemany('INSERT OR IGNORE INTO curation_observations VALUES(?,?,?)',
            [(run_id,o['id'],json.dumps(o,ensure_ascii=False)) for o in observations])
    return summary,folder


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs',type=Path,required=True)
    parser.add_argument('--original',type=Path,required=True)
    parser.add_argument('--profile',type=Path,required=True)
    parser.add_argument('--decisions',type=Path,required=True)
    parser.add_argument('--observations',type=Path)
    parser.add_argument('--root',type=Path,default=Path('.local/stage3/curation'))
    args=parser.parse_args()
    audit=json.loads(args.inputs.read_text());original=json.loads(args.original.read_text())
    records,cues,receipts=load_pack(audit['inputs'],original)
    profile=json.loads(args.profile.read_text());decisions=json.loads(args.decisions.read_text())
    observations=json.loads(args.observations.read_text()) if args.observations else []
    summary,folder=run_cycle(profile['city_id'],records,cues,receipts,decisions,profile,observations,args.root)
    print(json.dumps({'folder':str(folder),'summary':summary},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
