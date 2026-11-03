"""Offline annotation recovery; quarantine unsupported vocabulary, never invent tags."""
import argparse
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path

from .extraction import fingerprint
from .unattended import immutable_write, validate_annotations


def recover(chunk, response, registry):
    # Slot/evidence/text errors are not repaired by guessing. Only vocabulary
    # quarantine and mechanical accounting are allowed in this offline pass.
    candidate = deepcopy(response); events = []; quarantine = []
    if not isinstance(candidate,dict) or set(candidate)!={'records'}:
        raise ValueError('Malformed response cannot be recovered')
    entries = {e['record_id']:e for e in chunk['payload']['entries']}
    if set(candidate['records'])!=set(entries): raise ValueError('Missing/unknown record slots')
    for record_id, result in candidate['records'].items():
        before = fingerprint(result); keep = []
        for facet in result['facets']:
            values = registry['closed_values'].get(facet['key'])
            if values is not None and facet['value'] not in values:
                item = {'record_id':record_id,'name':entries[record_id]['name'],
                    'facet':deepcopy(facet),'status':'taxonomy_value_unsupported_semantics_not_rejected',
                    'reason':'Outside frozen closed vocabulary; source comparison needed before registry admission'}
                quarantine.append(item)
                events.append({'record_id':record_id,'action':'quarantine_unsupported_facet',
                    'facet_sha256':fingerprint(facet),'key':facet['key'],'value':facet['value']})
            else: keep.append(facet)
        result['facets'] = keep
        available = {c['id'] for c in entries[record_id]['claims']}
        used = {i for name in ('facets','details','activity_fit_proposals') for item in result[name] for i in item['claim_ids']}
        old = result['unrepresented_claim_ids']
        if not used<=available or not set(old)<=available:
            raise ValueError('Cannot recover foreign/invented evidence')
        remaining = sorted(available-used)
        if old!=remaining:
            # Sorting alone is not an accounting correction.
            added = set(remaining)-set(old); removed = set(old)-set(remaining)
            if added or removed or len(old)!=len(set(old)):
                events.append({'record_id':record_id,'action':'reconcile_unrepresented_accounting',
                    'added_unrepresented_claim_ids':sorted(added),
                    'removed_already_represented_claim_ids':sorted(removed),
                    'note':'Mechanical source accounting only, no factual/semantic approval'})
            result['unrepresented_claim_ids'] = remaining
        if fingerprint(result)!=before:
            events.append({'record_id':record_id,'action':'record_recovery_lineage',
                'before_sha256':before,'after_sha256':fingerprint(result)})
    # Check quarantined items' provenance too. Invalid evidence must never be
    # hidden by removing the annotation from the active proposal set.
    for item in quarantine:
        ids = item['facet']['claim_ids']; allowed={c['id'] for c in entries[item['record_id']]['claims']}
        if not ids or len(ids)!=len(set(ids)) or not set(ids)<=allowed:
            raise ValueError('Quarantined facet contains invalid evidence')
    validate_annotations(chunk,candidate,registry)
    return {'chunk_sha256':chunk['id'],'raw_candidate_sha256':fingerprint(response),
        'recovered_response_sha256':fingerprint(candidate),'response':candidate,
        'events':events,'quarantined_facets':quarantine,
        'approval':'protocol/evidence/accounting only; semantic manual review and canonical gates pending'}


def execute(prepared_path, output_root):
    prepared_path = Path(prepared_path); source_root = prepared_path.parent
    prepared = json.loads(prepared_path.read_text()); recovered = []; failed = []; manifest_inputs = []
    for stage in prepared['stages']:
        for chunk in stage['chunks']:
            if chunk['id']!=fingerprint({k:v for k,v in chunk.items() if k!='id'}):
                raise ValueError('Prepared source annotation input changed')
            path = source_root/stage['name']/(chunk['id']+'.candidate.json')
            if not path.exists():
                failed.append({'chunk_id':chunk['id'],'reason':'No saved raw candidate'}); continue
            raw = json.loads(path.read_text())
            if raw['chunk_sha256']!=chunk['id']: raise ValueError('Candidate bound to another request')
            manifest_inputs.append({'chunk_id':chunk['id'],'candidate_sha256':fingerprint(raw)})
            try: result = recover(chunk,raw['response'],prepared['registry'])
            except (ValueError,KeyError,TypeError) as exc:
                failed.append({'chunk_id':chunk['id'],'reason':str(exc)}); continue
            result['stage'] = stage['name']; result['source_entries'] = chunk['payload']['entries']
            recovered.append(result)
    manifest = {'prepared_sha256':fingerprint(prepared),'engine_sha256':fingerprint(Path(__file__).read_text()),
        'inputs':manifest_inputs,'registry_sha256':fingerprint(prepared['registry'])}
    folder = Path(output_root)/fingerprint(manifest)[:16]
    records = [r for c in recovered for r in c['response']['records'].values()]
    counts = Counter(e['action'] for c in recovered for e in c['events'])
    summary = {'planned_batches':sum(len(s['chunks']) for s in prepared['stages']),
        'recovered_batches':len(recovered),'protocol_valid_records':len(records),
        'batches_with_recovery_events':sum(any(e['action']!='record_recovery_lineage' for e in c['events']) for c in recovered),
        'events':dict(counts),'quarantined_facets':sum(len(c['quarantined_facets']) for c in recovered),
        'facet_proposals':sum(len(r['facets']) for r in records),
        'detail_proposals':sum(len(r['details']) for r in records),
        'activity_fit_proposals':sum(len(r['activity_fit_proposals']) for r in records),
        'unrepresented_source_claim_occurrences':sum(len(r['unrepresented_claim_ids']) for r in records),
        'failures':failed,'paid_calls':0,'approved_canonical_places':0,'planner_ready':False,
        'status':'offline_protocol_recovery_complete_semantic_review_pending' if not failed else 'partial_offline_recovery'}
    for name,document in {'manifest.json':manifest,'summary.json':summary,
        'annotation-proposals.json':{'manifest':manifest,'chunks':recovered,'ready_to_publish':False},
        'quarantined-facets.json':[q for c in recovered for q in c['quarantined_facets']]}.items():
        immutable_write(folder/name,document)
    return folder, summary


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared',type=Path,required=True)
    parser.add_argument('--output-root',type=Path,required=True)
    args=parser.parse_args();folder,summary=execute(args.prepared,args.output_root)
    print(json.dumps({'folder':str(folder),'summary':summary},ensure_ascii=False,indent=2))


if __name__=='__main__': main()
