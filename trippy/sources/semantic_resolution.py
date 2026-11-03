"""Offline, content-bound resolution of omitted/invalid source reviews.

Resolution completes review dispositions, not application of proposed repairs,
canonical identities, independent fact verification or planner publication.
"""
from collections import Counter
import argparse
from copy import deepcopy
import json
from pathlib import Path

from .extraction import fingerprint
from .coverage import private_write
from .semantic_review import load_review_cache, validate_review


def worklist(prepared, root):
    items = []; decisions = []
    for chunk in prepared['chunks']:
        if chunk['id'] != fingerprint({k:v for k,v in chunk.items() if k != 'id'}):
            raise ValueError('Prepared request changed')
        result = json.loads((Path(root)/(chunk['id']+'.json')).read_text())
        decisions.extend(load_review_cache(chunk, result)['decisions'])
        entries = {e['key']:e for e in chunk['payload']['entries']}
        cues = {c['segment_id']:c for c in chunk['payload']['original_context_cues']}
        for event in result.get('recovery_events', []):
            if event['disposition'] not in {'missing_source_review', 'invalid_source_review'}:
                continue
            entry = entries[event['key']]
            items.append({'chunk_id': chunk['id'], 'entry': entry, 'event': event,
                'context': [cues[k] for k in entry['context_segment_ids']]})
    keys = [d['key'] for d in decisions]
    if len(set(keys)) != len(keys) or len(keys) != prepared['claim_occurrences']:
        raise ValueError('Source review caches incomplete or duplicated')
    return {'version':1, 'prepared_sha256':fingerprint(prepared),
            'cached_decisions_sha256':fingerprint(decisions), 'items':items}, decisions


def resolve(prepared, root, manual):
    pending, original = worklist(prepared, root)
    if manual.get('review_method') != 'agent_source_comparison':
        raise ValueError('Explicit agent source comparison required')
    if manual.get('worklist_sha256') != fingerprint(pending):
        raise ValueError('Manual review inputs changed')
    submitted = manual['decisions']; supplied = [d['key'] for d in submitted]
    expected = {w['entry']['key']: w for w in pending['items']}
    if len(set(supplied)) != len(supplied) or set(supplied) != set(expected):
        raise ValueError('Every pending claim needs exactly one source disposition')
    replacements = {}; events = []
    for submitted_decision in submitted:
        decision = deepcopy(submitted_decision)
        entry = expected[decision['key']]['entry']
        if decision.pop('original_entry_sha256') != fingerprint(entry):
            raise ValueError('Manual decision targets stale claim/context')
        reviewed = validate_review({'payload':{'entries':[entry]}}, {'decisions':[decision]})['decisions'][0]
        reviewed['approval'] = 'agent_source_comparison_only; independent_fact_and_identity_review_pending'
        replacements[decision['key']] = reviewed
        events.append({'key':decision['key'], 'before_sha256':fingerprint(next(d for d in original if d['key']==decision['key'])),
                       'after_sha256':fingerprint(reviewed), 'review_method':manual['review_method']})
    effective = [replacements.get(d['key'], d) for d in original]
    not_reviewed = [d['key'] for d in effective if d['approval'].startswith('not_reviewed;')]
    return {'version':1, 'prepared_sha256':fingerprint(prepared), 'worklist_sha256':fingerprint(pending),
        'manual_decisions_sha256':fingerprint(manual), 'events':events, 'decisions':effective,
        'summary':{'claims_accounted':len(effective), 'targeted_claims_reviewed':len(replacements),
            'missing_or_invalid_reviews_remaining':len(not_reviewed),
            'source_disposition_pass_complete':not not_reviewed,
            'actions':dict(Counter(d['action'] for d in effective)), 'planner_ready':False,
            'repair_application':'pending; original normalized dataset unchanged',
            'remaining':'Repair adjudication, unresolved identities/subjects, independent/current facts, coverage and planner scenarios'},
        'paid_model_calls':0}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared', required=True, type=Path)
    parser.add_argument('--cache-root', required=True, type=Path)
    parser.add_argument('--manual', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = resolve(json.loads(args.prepared.read_text()), args.cache_root,
                     json.loads(args.manual.read_text()))
    if args.output.exists():
        if json.loads(args.output.read_text()) != result:
            raise ValueError('Resolution output changed; version the artifact')
    else:
        private_write(args.output, result)
    print(json.dumps(result['summary'], indent=2))


if __name__ == '__main__': main()
