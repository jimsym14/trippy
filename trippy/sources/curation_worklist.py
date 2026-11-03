"""Versioned quality work queue: shared evidence, trip checks and private behavior."""
import argparse
from collections import Counter
import json
from pathlib import Path

from .coverage import private_write
from .extraction import fingerprint


CRITICAL = {'accessibility', 'dietary', 'safety', 'opening_hours', 'tickets', 'price'}


def build_worklist(cycle, profile):
    cycle = Path(cycle)
    normalized = json.loads((cycle / 'normalized.json').read_text())
    summary = json.loads((cycle / 'summary.json').read_text())
    coverage = json.loads((cycle / 'coverage.json').read_text())
    if profile['city_id'] != summary['city_id']:
        raise ValueError('Coverage profile belongs to another city')
    cell_ids = [c['id'] for c in profile['coverage_cells']]
    if len(set(cell_ids)) != len(cell_ids) or set(cell_ids) != {c['id'] for c in coverage}:
        raise ValueError('Profile/coverage cells must match exactly with unique IDs')
    tasks = []
    for record in normalized['drafts']:
        dimensions = {c['dimension'] for c in record['claims']}
        tasks.append({'type': 'source_semantic_review', 'scope': 'shared',
            'priority': 0 if dimensions & CRITICAL else 2,
            'occurrence_id': record['id'], 'record_sha256': fingerprint(record),
            'name': record['name'], 'claim_count': len(record['claims']),
            'required_checks': ['subject_and_own_name', 'claim_matches_full_source_context',
                'negation_and_time_scope', 'dimensions_and_intent_fit', 'preserve_opinions_and_uncertainty',
                'retain_unresolved_detail_without_guessing_a_place'],
            'status': 'pending_exhaustive_review'})
        if record['identity_uncertain'] or record['kind'] == 'venue':
            tasks.append({'type': 'transcript_identity_review', 'scope': 'shared', 'priority': 1,
                'occurrence_id': record['id'], 'record_sha256': fingerprint(record), 'name': record['name'],
                'required_checks': ['original_name_and_context', 'branch_and_alias_evidence',
                    'source_identity_then_coordinate_and_entrance', 'avoid_transferring_claims_between_subjects'],
                'status': 'pending; lexical candidates do not approve identity'})
    for cell in coverage:
        tasks.append({'type': {'shared': 'city_evidence_depth_review', 'on_demand': 'runtime_discovery_contract',
            'trip_check': 'selected_trip_validation_contract', 'private_trip': 'private_planner_acceptance'}[cell['scope']],
            'scope': cell['scope'], 'priority': 2 if cell['state'] == 'no_candidate_detected' else 3,
            'coverage_cell_id': cell['id'], 'candidate_state': cell['state'],
            'canonical_verified_options': cell['canonical_verified_options'],
            'query_templates': cell['query_variants'],
            'required_checks': ['distinct_relevant_options', 'source_independence_and_recency',
                'areas_prices_effort_and_preference_diversity', 'constraints_supported_or_explicitly_unknown'],
            'status': 'pending; requires reviewed evidence or demonstrated runtime behavior'})
    receipts = []; inventories = []
    for receipt in normalized['upstream_receipts']:
        path = Path(receipt['path']); source = json.loads(path.read_text())
        if fingerprint(source) != receipt['sha256']:
            raise ValueError('Upstream review inventory changed')
        receipts.append(receipt)
        sections = []
        for field in ('review_queue', 'review_issues', 'execution_failures', 'primary_failures'):
            if source.get(field):
                sections.append({'json_path': field, 'entries': len(source[field])})
        for i, audit in enumerate(source.get('audit_results', [])):
            if audit.get('quarantine'):
                sections.append({'json_path': f'audit_results[{i}].quarantine', 'entries': len(audit['quarantine'])})
        for field in ('final_check', 'prior_final_check'):
            check = source.get(field) or {}
            if check.get('review_queue'):
                sections.append({'json_path': field + '.review_queue', 'entries': len(check['review_queue'])})
        if sections:
            inventories.append({'path': str(path), 'sha256': receipt['sha256'], 'sections': sections,
                'count_semantics': 'Source review entries may overlap; not unique missing facts',
                'status': 'pending_source_comparison_and_disposition'})
    tasks.sort(key=lambda t: (t['priority'], t['type'], t.get('occurrence_id', t.get('coverage_cell_id', ''))))
    spec = {'engine_sha256': fingerprint(Path(__file__).read_text()), 'curation_run_id': summary['run_id'],
            'profile_sha256': fingerprint(profile), 'upstream_receipts': receipts}
    return {'manifest': spec, 'tasks': tasks, 'upstream_review_inventory': inventories,
        'summary': {'tasks': len(tasks), 'tasks_by_type': dict(Counter(t['type'] for t in tasks)),
            'tasks_by_scope': dict(Counter(t['scope'] for t in tasks)),
            'critical_source_review_records': sum(t['type'] == 'source_semantic_review' and t['priority'] == 0 for t in tasks),
            'upstream_inventory_documents': len(inventories), 'ready_to_publish': False,
            'automation_boundary': 'Queue creation and replay are automated; source review, web discovery and planner integration are not yet an unattended end-to-end process'},
        'iteration_policy': {'quality_before_cost': True,
            'promote_only_after': ['source_semantic_review', 'canonical_branch_and_entrance',
                'independent_field_provenance_and_freshness', 'reviewed_scenario_alternatives',
                'planner_acceptance_execution', 'safe_unknowns_and_private_ownership'],
            'measure_each_cycle': ['new_supported_details', 'resolved_or_rejected_identities',
                'unresolved_conflicts', 'quarantine_dispositions', 'distinct_options_by_intent_and_area',
                'source_independence', 'reviewed_sample_errors_and_omissions', 'actual_api_usage', 'cache_reuse'],
            'stop_rule': 'Reviewed scoped acceptance cases pass without known critical defects; no universal-perfect-dataset or 100% fairness claim',
            'no_progress_rule': 'Change source, method or missing-evidence strategy; do not repeat identical paid extraction',
            'runtime_rule': 'Shared stable evidence is reused; volatile dates/prices/availability and exact spatial/niche needs are checked for the selected trip'}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cycle', type=Path, required=True)
    parser.add_argument('--profile', type=Path, required=True)
    args = parser.parse_args()
    result = build_worklist(args.cycle, json.loads(args.profile.read_text()))
    output = args.cycle / ('worklist-' + fingerprint(result)[:16] + '.json')
    if output.exists():
        if json.loads(output.read_text()) != result:
            raise ValueError('Immutable worklist differs')
    else:
        private_write(output, result)
    print(json.dumps({'output': str(output), 'summary': result['summary']}, indent=2))


if __name__ == '__main__':
    main()
