"""Replayable local curation recipe with measured stage receipts and no paid calls."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
from time import perf_counter

from .coverage import private_write
from .curation_cycle import load_pack, run_cycle
from .curation_worklist import build_worklist
from .extraction import fingerprint
from .identity_review import run_review, review_source_links


def immutable(path, document):
    if path.exists():
        if json.loads(path.read_text()) != document:
            raise ValueError('Existing immutable pipeline artifact differs')
    else:
        private_write(path, document)


def execute(recipe):
    started = perf_counter(); stages = []
    def stage(name, function):
        print(f'Start: {name}', flush=True)
        before = perf_counter(); result = function()
        stages.append({'stage': name, 'elapsed_seconds': round(perf_counter()-before, 4)})
        print(f'Complete: {name}', flush=True)
        return result
    def read(name):
        return json.loads(Path(recipe[name]).read_text())
    audit = read('inputs'); original = read('original'); profile = read('profile')
    decisions = read('decisions'); observations = read('observations')
    records, cues, receipts = stage('load and validate effective sources', lambda: load_pack(audit['inputs'], original))
    base, baseline_folder = stage('baseline', lambda: run_cycle(profile['city_id'], records, cues, receipts,
        [], profile, [], recipe['root']))
    corrected, folder = stage('source corrections and coverage', lambda: run_cycle(profile['city_id'],
        records, cues, receipts, decisions, profile, observations, recipe['root']))
    identity_path, identity_summary = stage('read-only catalog matching', lambda: run_review(folder,
        recipe['catalog'], recipe['catalog_city_id'], recipe['catalog_version_id']))
    identity = json.loads(identity_path.read_text())
    reviewed = stage('content-bound identity decisions', lambda: review_source_links(identity,
        read('identity_decisions') if recipe.get('identity_decisions') else []))
    reviewed_path = folder / ('source-identity-decisions-'+fingerprint(reviewed)[:16]+'.json')
    immutable(reviewed_path, reviewed)
    worklist = stage('quality work queue', lambda: build_worklist(folder, profile))
    worklist_path = folder / ('worklist-'+fingerprint(worklist)[:16]+'.json')
    immutable(worklist_path, worklist)
    report = {'recipe_sha256': fingerprint(recipe), 'curation_run_id': corrected['run_id'],
        'baseline': str(baseline_folder), 'corrected': str(folder), 'identity_review': str(identity_path),
        'identity_decisions': str(reviewed_path), 'worklist': str(worklist_path),
        'metrics': {'records': corrected['after']['records'], 'claims': corrected['after']['claims'],
            'editorial_decisions': corrected['editorial_corrections'],
            'primary_source_observations': corrected['external_observations'],
            'claim_dimensions_before': base['after']['claim_dimensions'],
            'claim_dimensions_after': corrected['after']['claim_dimensions'],
            'diagnostic_cells_without_candidates_before': base['cells_without_detected_candidates'],
            'diagnostic_cells_without_candidates_after': corrected['cells_without_detected_candidates'],
            'identity_matching': identity_summary, 'reviewed_identity_links': reviewed['summary'],
            'work_queue': worklist['summary']},
        'model_api_calls': 0, 'provider_charges_in_this_recipe': '0', 'catalog_writes': 0,
        'ready_to_publish': False, 'ready_for_complete_planner': False,
        'measurement_limitations': 'No measured planner accuracy, total compute cost or universal fairness. External source research is reviewed input, not automated by this command.'}
    report_path = folder / ('pipeline-report-'+fingerprint(report)[:16]+'.json')
    immutable(report_path, report)
    stamp = datetime.now(timezone.utc).isoformat()
    execution = {'executed_at': stamp, 'report': str(report_path), 'stages': stages,
        'elapsed_seconds': round(perf_counter()-started, 4), 'model_api_calls': 0,
        'repeat_behavior': 'Inputs and editorial decisions are reused; stage artifacts are immutable, timing receipt is per execution'}
    private_write(folder / ('execution-'+fingerprint(execution)[:16]+'.json'), execution)
    return report_path, report, execution


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', type=Path, required=True)
    args = parser.parse_args()
    path, report, execution = execute(json.loads(args.recipe.read_text()))
    print(json.dumps({'report': str(path), 'editorial_decisions': report['metrics']['editorial_decisions'],
        'reviewed_source_links': report['metrics']['reviewed_identity_links']['reviewed_source_links'],
        'elapsed_seconds': execution['elapsed_seconds'], 'model_api_calls': 0, 'ready_to_publish': False}, indent=2))


if __name__ == '__main__':
    main()
