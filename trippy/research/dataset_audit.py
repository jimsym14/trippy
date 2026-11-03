"""Read-only before/after checks; admission coverage is not accuracy."""
import argparse
from collections import Counter
import json
from pathlib import Path

from trippy.research.dataset_integration import verify_snapshot
from trippy.sources.extraction import fingerprint
from trippy.sources.unattended import immutable_write


def require(condition, message):
    if not condition:
        raise ValueError(message)


def slots(pack, held):
    keys = [m['upstream_key'] for r in pack['drafts'] for m in r['claim_review_metadata']]
    keys += [h['key'] for h in held]
    require(len(keys) == len(set(keys)), 'Duplicate claim occurrence')
    return set(keys)


def audit(selection, recipe):
    read = lambda p: json.loads(Path(p).read_text())
    bundle = read(selection['dataset'])
    old, held = read(recipe['pack']), read(recipe['held'])
    final = bundle['normalized']
    require(fingerprint(bundle) == selection['bundle_sha256'], 'Active pointer hash mismatch')
    require(slots(old, held) == slots(final, bundle['held_claims']), 'Lost or invented source slots')
    before_records = {r['upstream_occurrence_id']: r for r in old['drafts']}
    require(set(before_records) == {r['upstream_occurrence_id'] for r in final['drafts']}, 'Record occurrence loss')
    for r in final['drafts']:
        previous = before_records[r['upstream_occurrence_id']]
        for field in previous:
            if field in {'claims', 'claim_review_metadata'}:
                require(r[field][:len(previous[field])] == previous[field], 'Previous claim/decision changed')
            elif field != 'id':
                require(r[field] == previous[field], 'Previous record metadata changed: '+field)
    old_annotations = read(recipe['annotations'])
    originals = {a['key']: a for a in old_annotations['annotations']}
    require(len(originals) == len(bundle['annotations']), 'Annotation slot count changed')
    for a in bundle['annotations']:
        previous = originals[a['key']]
        for field in ('original_entry', 'effective', 'manual_decision', 'upstream_automated_result', 'unapplied_suggestions'):
            require(a[field] == previous[field], 'Annotation provenance or decision changed')
        require(fingerprint(a['original_entry']) == a['source_entry_sha256'], 'Stale annotation provenance')
        if a['manual_decision']:
            require(a['claim_binding_current'], 'Manual annotation lost evidence binding')
    require(bundle['operational'] == read(recipe['operational']), 'Operational evidence changed')
    require(bundle['identity_links'] == read(recipe['identity_links']), 'Identity lineage changed')
    verify_snapshot(selection['database'], bundle)
    annotations = bundle['annotations']
    manually_reviewed = [a for a in annotations if a['manual_decision']]
    eligible = [a for a in annotations if a['source_discovery_eligible']]
    candidates = sum(bool((a['upstream_automated_result'] or {}).get('source_discovery_candidate')) for a in annotations)
    counts = lambda items: dict(sorted(Counter(items).items()))
    labels = lambda items: counts(
        a['effective']['kind']+':'+str(a['effective']['proposal'].get('key', a['effective']['proposal'].get('activity_id', 'activity')))+':'+str(a['effective']['proposal'].get('value', ''))
        for a in items)
    return {
        'checks': {'occurrence_conservation': True, 'previous_record_metadata_unchanged': True,
                   'annotation_provenance_unchanged': True, 'manual_bindings_current': True,
                   'operator_identity_inputs_unchanged': True, 'sqlite_json_full_parity': True},
        'bundle_sha256': fingerprint(bundle), 'source_slots': len(slots(old, held)),
        'record_occurrences': len(final['drafts']),
        'video_sources_before': len({r['source']['external_id'] for r in old['drafts']}),
        'video_sources_after': len({r['source']['external_id'] for r in final['drafts']}),
        'readiness': bundle['readiness'], 'source_actions': bundle['source_review_actions'],
        'manual_annotation_actions': counts(a['manual_decision']['action'] for a in manually_reviewed),
        'manual_kind_movements': counts(a['original_entry']['kind']+' -> '+a['effective']['kind'] for a in manually_reviewed),
        'automated_discovery_candidates_not_approvals': candidates,
        'new_manual_discovery_eligible': len(eligible),
        'previous_manual_discovery_eligible': sum(bool(a['source_discovery_eligible']) for a in bundle['preserved_manual_reviews']),
        'eligible_new_annotation_labels': labels(eligible),
        'pending_annotation_evidence_bindings': counts(str(a['claim_binding_current']) for a in annotations if not a['manual_decision']),
        'unapplied_suggestions_retained': sum(len(a['unapplied_suggestions']) for a in annotations),
        'paid_calls': 0, 'http_requests': 0,
        'limits': ['Conservation verifies stored lineage, not completeness against entire videos.',
                   'Manual review coverage and admission are not estimated factual accuracy.',
                   'Discovery candidates and eligible annotations are different approval scopes.',
                   'Snapshot validation does not test application retrieval or itineraries.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--selection', type=Path, required=True)
    parser.add_argument('--recipe', type=Path, required=True)
    parser.add_argument('--output-root', type=Path, required=True)
    args = parser.parse_args()
    result = audit(json.loads(args.selection.read_text()), json.loads(args.recipe.read_text()))
    output = args.output_root / fingerprint(result)[:16] / 'audit.json'
    immutable_write(output, result)
    print(json.dumps({'output': str(output), **result}, indent=2))


if __name__ == '__main__':
    main()
