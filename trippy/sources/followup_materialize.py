"""Apply explicit, content-bound expanded source reviews to a private pack.

This is an editorial stage. Neither agreement nor an exact-venue assertion
approves a canonical identity, current capability, or planner fact.
"""
from collections import Counter
from copy import deepcopy
from pathlib import Path

from .curation_cycle import validate_pack
from .extraction import Claim, fingerprint
from .semantic_review import validate_review


SCOPES = {'exact_venue', 'area', 'general', 'visit_context',
          'comparison_context', 'subvenue_unspecified', 'creator_biography',
          'creator_trip', 'source_link_hint', 'identity_unresolved'}
LIFECYCLES = {'source_description', 'creator_opinion', 'historical_operation',
              'planning_estimate', 'archival', 'uncertain'}


def materialize(pack, held, prepared, handoff, cues, document):
    bindings = {'pack_sha256': fingerprint(pack), 'held_sha256': fingerprint(held),
                'prepared_sha256': fingerprint(prepared), 'handoff_sha256': fingerprint(handoff)}
    if document.get('bindings') != bindings:
        raise ValueError('Manual followup belongs to stale inputs')
    if document.get('review_method') != 'agent_expanded_source_comparison':
        raise ValueError('Explicit expanded source comparison required')
    if handoff['prepared_sha256'] != fingerprint(prepared):
        raise ValueError('Handoff prepared context differs')
    entries = {e['key']: e for c in prepared['chunks'] for e in c['payload']['entries']}
    pending = {h['key']: deepcopy(h) for h in held}
    if len(pending) != len(held) or set(entries) != set(pending):
        raise ValueError('Expanded entries must exactly cover held claims')
    records = deepcopy(pack['drafts'])
    by_upstream = {r['upstream_occurrence_id']: r for r in records}
    before_keys = [m['upstream_key'] for r in records for m in r['claim_review_metadata']] + list(pending)
    if len(set(before_keys)) != len(before_keys):
        raise ValueError('Duplicate upstream claims')
    changed = set(); seen = set(); events = []; counts = Counter()
    for supplied in document['decisions']:
        key = supplied['key']
        if key not in pending or key in seen:
            raise ValueError('Unknown or duplicate followup claim')
        seen.add(key); entry = entries[key]; old = pending[key]
        if supplied['original_entry_sha256'] != fingerprint(entry):
            raise ValueError('Stale expanded claim/context')
        if (entry['occurrence_id'] != old['upstream_occurrence_id'] or
                entry['claim'] != old['original_claim']):
            raise ValueError('Expanded claim differs from held original')
        if supplied['assertion_scope'] not in SCOPES or supplied['lifecycle'] not in LIFECYCLES:
            raise ValueError('Explicit assertion scope and lifecycle required')
        if not supplied.get('subject_note'):
            raise ValueError('Explicit subject qualification required')
        clean = {k: supplied[k] for k in ('key', 'action', 'dimension', 'value', 'basis',
                    'evidence_segment_ids', 'use_scope', 'reason')}
        decision = validate_review({'payload': {'entries': [entry]}}, {'decisions': [clean]})['decisions'][0]
        evidence = []
        for segment in decision['evidence_segment_ids']:
            cue = cues.get(segment)
            if cue is None or segment.rsplit(':', 1)[0] != entry['source_id']:
                raise ValueError('Evidence missing or belongs to another source')
            evidence.append({k: cue[k] for k in ('segment_id', 'start_seconds', 'end_seconds')} | {'quote': cue['text']})
        if not evidence:
            raise ValueError('Source comparison needs actual evidence')
        annotation = {k: supplied[k] for k in ('assertion_scope', 'lifecycle', 'subject_note')}
        annotation.update(review_kind='agent_expanded_source_comparison',
            manual_document_sha256=fingerprint(document), expanded_entry_sha256=fingerprint(entry),
            source_comparison_evidence=evidence, independently_verified=False,
            current_trip_verified=False, canonical_identity_verified=False,
            planner_fact_eligible=False, use_scope=decision['use_scope'])
        counts[decision['action']] += 1
        if decision['action'] == 'unresolved':
            old.update(state='held_unresolved', followup_review=decision,
                       followup_metadata=annotation)
            continue
        claim = deepcopy(old['original_claim'])
        if decision['action'] == 'repair':
            claim.update({k: decision[k] for k in ('dimension', 'value', 'basis')})
            claim['citations'] = evidence
        Claim.model_validate(claim)
        record = by_upstream[old['upstream_occurrence_id']]
        record['claims'].append(claim)
        record['claim_review_metadata'].append(annotation | {'claim_sha256': fingerprint(claim),
            'upstream_key': key, 'state': 'source_repair_applied' if decision['action']=='repair' else 'source_supported'})
        changed.add(record['id']); del pending[key]
        events.append({'key': key, 'original_claim': old['original_claim'], 'accepted_claim': claim,
                       'decision': decision, 'metadata': annotation})
    mapping = {}
    for record in records:
        previous_id = record['id']
        if previous_id in changed:
            record['id'] = fingerprint({'previous_id': previous_id, 'claims': record['claims'],
                                       'reviews': record['claim_review_metadata']})
        mapping[previous_id] = record['id']
    after_keys = [m['upstream_key'] for r in records for m in r['claim_review_metadata']] + list(pending)
    if sorted(before_keys) != sorted(after_keys):
        raise ValueError('Followup lost or duplicated upstream claims')
    validate_pack(records, cues)
    manifest = bindings | {'manual_document_sha256': fingerprint(document), 'version': 1,
                           'engine_sha256': fingerprint(Path(__file__).read_text()),
                           'cues_sha256': fingerprint(cues)}
    return {'manifest': manifest, 'run_id': fingerprint(manifest),
        'normalized': {**deepcopy(pack), 'drafts': records,
            'upstream_to_normalized_ids': {r['upstream_occurrence_id']: r['id'] for r in records},
            'previous_to_normalized_ids': mapping, 'ready_to_publish': False},
        'held_claims': list(pending.values()), 'editorial_events': events,
        'summary': {'manual_followup_reviews': len(seen), 'actions': dict(counts),
            'active_source_claims': sum(len(r['claims']) for r in records),
            'held_claims': len(pending), 'claims_preserved_in_active_or_held': len(after_keys),
            'changed_records': len(changed), 'paid_model_calls': 0,
            'approved_canonical_places': 0, 'planner_ready': False}}


def main():
    import argparse
    import json
    from .curation_cycle import load_pack
    from .semantic_materialize import write_artifact
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', type=Path, required=True)
    args = parser.parse_args()
    read = lambda path: json.loads(Path(path).read_text())
    recipe = read(args.recipe)
    source = read(recipe['source_recipe'])
    _, cues, _ = load_pack(read(source['inputs'])['inputs'], read(source['original']))
    result = materialize(read(recipe['pack']), read(recipe['held']), read(recipe['prepared']),
                         read(recipe['handoff']), cues, read(recipe['manual_document']))
    folder = write_artifact(recipe['output_root'], result)
    print(json.dumps({'folder': str(folder), 'summary': result['summary']}, indent=2))


if __name__ == '__main__':
    main()
