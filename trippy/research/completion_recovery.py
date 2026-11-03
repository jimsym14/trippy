"""Offline per-item recovery of frozen completion candidates. Never paid-retries."""
import argparse
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path
import sqlite3

from trippy.sources.extraction import Claim, fingerprint
from trippy.sources.unattended import immutable_write
from .reviews import validate_source, validate_annotations, validate_page


def recover_item(request, key, fields, *, source=False):
    entries={e['key']:e for e in request['payload']['entries']}; entry=entries[key]
    candidate=deepcopy(fields); events=[]; suggestions=[]
    evidence_field='evidence_segment_ids' if source else 'evidence_claim_ids'
    evidence=candidate.get(evidence_field)
    if isinstance(evidence,list) and len(set(evidence))!=len(evidence):
        candidate[evidence_field]=list(dict.fromkeys(evidence))
        events.append('deduplicated_identical_evidence_references')
    if not source and candidate.get('action')!='repair':
        replacement=(candidate.get('replacement_key'),candidate.get('replacement_value'))
        if replacement!=(None,None):
            proposal=entry['proposal']
            same=replacement==(proposal.get('key'),proposal.get('value'))
            if not same:
                suggestions.append({'replacement_key':replacement[0],'replacement_value':replacement[1],
                    'action':candidate['action'],'status':'unapplied_text_suggestion_requires_source_review'})
            if candidate['action']=='retain' and not same:
                candidate['action']='unresolved'
                candidate['reason']='Implicit replacement conflicts with retain; original annotation remains unapproved pending source comparison.'
                events.append('quarantined_implicit_repair')
            else: events.append('removed_redundant_replacement' if same else 'separated_unapplied_context_suggestion')
            candidate.update(replacement_key=None,replacement_value=None)
    subset=deepcopy(request); subset['payload']['entries']=[entry]
    validated=(validate_source if source else validate_annotations)(subset,{'decisions':{key:candidate}})['decisions'][0]
    return {'entry':deepcopy(entry),'decision':validated,'events':events,'unapplied_suggestions':suggestions,
            'original_fields_sha256':fingerprint(fields)}


def recover_request(request,response,kind):
    if kind=='operator_extract':
        return {'page':validate_page(request,response),'items':[],'quarantine':[]}
    if not isinstance(response,dict) or set(response)!={'decisions'} or not isinstance(response['decisions'],dict):
        raise ValueError('Malformed keyed candidate cannot be mechanically recovered')
    expected={e['key']:e for e in request['payload']['entries']}
    if set(response['decisions'])!=set(expected):
        raise ValueError('Foreign/missing keyed slots require explicit review')
    items=[]; quarantine=[]
    for key,fields in response['decisions'].items():
        try: item=recover_item(request,key,fields,source=kind=='source'); items.append(item)
        except (ValueError,TypeError,KeyError) as exc:
            quarantine.append({'key':key,'entry':expected[key],'original_fields':deepcopy(fields),
                'error_type':type(exc).__name__,'reason':'Per-item schema/evidence/taxonomy source review required',
                'original_fields_sha256':fingerprint(fields),'planner_fact_eligible':False})
    if len(items)+len(quarantine)!=len(expected): raise ValueError('Recovery lost an annotation/claim slot')
    return {'items':items,'quarantine':quarantine}


def execute(root):
    root=Path(root); prepared=json.loads((root/'prepared.json').read_text()); results=[]; inputs=[]
    with sqlite3.connect(root/'jobs.sqlite') as db:
        rows=list(db.execute('SELECT spec,state FROM jobs ORDER BY ordinal'))
    for spec_json,state in rows:
        spec=json.loads(spec_json); kind=spec['kind']
        if kind not in {'source','facets','details','activity_fit'}: continue
        request=spec['payload']['request']; path=root/'candidates'/(request['id']+'.json')
        if not path.exists(): continue
        raw=json.loads(path.read_text())
        if raw['chunk_sha256']!=request['id']: raise ValueError('Candidate bound to another request')
        inputs.append({'job_sha256':spec['id'],'candidate_sha256':fingerprint(raw)})
        recovered=recover_request(request,raw['response'],kind)
        results.append({'kind':kind,'request':request,'upstream_job_state':state,**recovered})
    manifest={'prepared_sha256':fingerprint(prepared),'candidate_inputs':inputs,
        'engine_sha256':fingerprint(Path(__file__).read_text()),'version':1}
    source_items=[i for r in results if r['kind']=='source' for i in r['items']]
    annotations=[i for r in results if r['kind']!='source' for i in r['items']]
    quarantine=[{'kind':r['kind'],**i} for r in results for i in r['quarantine']]
    events=Counter(event for r in results for item in r['items'] for event in item['events'])
    staged=deepcopy(json.loads((root/'staged-source-pack.json').read_text()))
    records=staged['drafts']; held={h['key']:h for h in staged['held_claims']}
    by_upstream={r['upstream_occurrence_id']:r for r in records}
    active_keys={m['upstream_key'] for r in records for m in r['claim_review_metadata']}
    cue_inventory={c['segment_id']:c for r in results if r['kind']=='source'
                   for c in r['request']['payload']['original_context_cues']}
    applied=0; changed=set()
    for item in source_items:
        d=item['decision']; key=d['key']
        if key in active_keys: continue
        original=held.get(key)
        if original is None: raise ValueError('Recovered source key is absent from active/held pack')
        if item['entry']['claim']!=original['original_claim']: raise ValueError('Recovered source claim changed')
        if d['action']=='unresolved':
            original['recovered_followup']=d; continue
        claim=deepcopy(original['original_claim'])
        if d['action']=='repair':
            claim.update({f:d[f] for f in ('dimension','value','basis')})
            claim['citations']=[{f:cue_inventory[s][f] for f in ('segment_id','start_seconds','end_seconds')} |
                {'quote':cue_inventory[s]['text']} for s in d['evidence_segment_ids']]
        Claim.model_validate(claim); record=by_upstream[original['upstream_occurrence_id']]
        record['claims'].append(claim); changed.add(record['id'])
        record['claim_review_metadata'].append({'upstream_key':key,'claim_sha256':fingerprint(claim),
            'state':'automated_editorial_candidate','assertion_scope':d['assertion_scope'],
            'lifecycle':d['lifecycle'],'subject_note':d['subject_note'],'review_kind':'offline_protocol_recovered_source_comparison',
            'manual_reviewed':False,'canonical_identity_verified':False,'current_trip_verified':False,'planner_fact_eligible':False})
        staged['editorial_events'].append({'key':key,'original_claim':original['original_claim'],
            'candidate_claim':claim,'decision':d,'recovery_events':item['events']})
        del held[key]; active_keys.add(key); applied+=1
    mapping={}
    for record in records:
        before=record['id']
        if before in changed:
            record['id']=fingerprint({'previous_id':before,'claims':record['claims'],'reviews':record['claim_review_metadata']})
        mapping[before]=record['id']
    staged['held_claims']=list(held.values())
    staged['previous_to_staged_ids']={base:mapping[old] for base,old in staged['previous_to_staged_ids'].items()}
    original_count=sum(len(r['claims']) for r in json.loads((root/'staged-source-pack.json').read_text())['drafts'])+len(json.loads((root/'staged-source-pack.json').read_text())['held_claims'])
    keys=[m['upstream_key'] for r in records for m in r['claim_review_metadata']]+list(held)
    if len(keys)!=len(set(keys)) or len(keys)!=original_count: raise ValueError('Source conservation failed')
    source_summary=Counter(i['decision']['action'] for i in source_items)
    annotation_summary=Counter(i['decision']['action'] for i in annotations)
    summary={'validated_source_slots':len(source_items),'source_actions':dict(source_summary),
        'validated_annotation_slots':len(annotations),'annotation_actions':dict(annotation_summary),
        'quarantined_slots':len(quarantine),'quarantined_by_kind':dict(Counter(q['kind'] for q in quarantine)),
        'protocol_recovery_events':dict(events),'newly_added_staged_claims':applied,
        'staged_active_claims':sum(len(r['claims']) for r in records),'held_claims':len(held),
        'source_claims_conserved':len(keys),'paid_model_calls':0,'http_calls':0,
        'canonical_identities_admitted':0,'ready_to_publish':False}
    folder=root.parent/'completion-recovery-v1'/fingerprint(manifest)[:16]
    for name,doc in {'manifest.json':manifest,'summary.json':summary,'annotation-items.json':annotations,
        'source-items.json':source_items,'quarantined-items.json':quarantine,'staged-source-pack.json':staged}.items():
        immutable_write(folder/name,doc)
    return folder,summary


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run',type=Path,required=True)
    args=parser.parse_args();folder,summary=execute(args.run)
    print(json.dumps({'folder':str(folder),'summary':summary},ensure_ascii=False,indent=2))


if __name__=='__main__':main()
