"""Run actual knowledge queries and report missing gates without inventing accuracy."""
import argparse
import json
from pathlib import Path

from trippy.sources.coverage import private_write
from trippy.sources.extraction import fingerprint
from .knowledge import Knowledge


def evaluate(knowledge, scenarios):
    cases = []
    for case in scenarios['cases']:
        variants = [knowledge.search(request) for request in case['variants']]
        cases.append({'id': case['id'], 'request': case['request'], 'query_results': variants,
            'distinct_canonical_candidates': len({r['place_id'] for v in variants for r in v['items']}),
            'state': 'needs_evidence_or_integration' if any(v['gaps'] or not v['items'] for v in variants)
                     else 'discovery_available_selected_trip_checks_pending',
            'required_integration': case['required_integration'],
            'planner_itinerary_executed': False, 'ready': False})
    return {'knowledge_version': knowledge.document['version'], 'scenario_sha256': fingerprint(scenarios),
        'cases': cases, 'summary': {'scenario_families': len(cases),
            'query_variants_executed': sum(len(c['query_results']) for c in cases),
            'families_needing_evidence_or_integration': sum(c['state']=='needs_evidence_or_integration' for c in cases),
            'complete_itineraries_executed': 0, 'planner_ready': False, 'model_api_calls': 0},
        'limitations': 'Actual retrieval evaluation only. Correct uncertainty is not a passing complete itinerary; no accuracy/fairness score assigned.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--knowledge', type=Path, required=True)
    parser.add_argument('--scenarios', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = evaluate(Knowledge.load(args.knowledge), json.loads(args.scenarios.read_text()))
    if args.output.exists():
        if json.loads(args.output.read_text()) != report: raise ValueError('Versioned evaluation differs')
    else: private_write(args.output, report)
    print(json.dumps(report['summary'], indent=2))


if __name__ == '__main__': main()
