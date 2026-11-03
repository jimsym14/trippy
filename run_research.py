"""Preview or explicitly execute the same pipeline used by the native app."""
import argparse
import json
import os
from pathlib import Path

from trippy_config import read_environment
from research_pipeline import build_scout_prompt
from trippy.planner.planning_contract import normalized_brief
from trippy.planner.research_context import selected_dataset, task_context, inventory_context
from trippy.planner.pipeline import SYSTEM, run, task_matrix
from trippy.planner.live_provider import AzureResearchProvider


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--brief',required=True,type=Path)
    parser.add_argument('--output-dir',type=Path,default=Path('/tmp/trippy-research-plan'))
    parser.add_argument('--execute',action='store_true',help='Explicitly dispatch configured billable web/Luna requests')
    args=parser.parse_args()
    root=Path(__file__).resolve().parent
    brief=normalized_brief(json.loads(args.brief.read_text()))
    dataset=selected_dataset(root,brief['destination'])
    args.output_dir.mkdir(parents=True,exist_ok=True,mode=0o700)
    (args.output_dir/'scout-prompt.txt').write_text(build_scout_prompt(brief))
    (args.output_dir/'synthesis-prompt.txt').write_text(SYSTEM)
    preview={'version':'trip-pipeline-v1','brief':brief,'dataset_version':dataset['version'],
        'dataset_state':dataset['state'],'source_occurrences_available':len(dataset['candidates']),
        'tasks':task_matrix(brief),'selected_checks':'After retrieval, in groups of four',
        'paid_calls_dispatched':0,'route_validation':'Requires a configured route provider or in-app MapKit preview'}
    retrieval=[]
    for task in preview['tasks']:
        context=task_context(dataset,task,brief)
        context['local_inventory']=inventory_context(root,brief['destination'],task)
        retrieval.append({'task':task,'local_evidence':context})
    preview['retrieval']=[{'task':r['task']['id'],'editorial_occurrences_selected':len(r['local_evidence']['candidates']),
        'inventory_candidates_selected':len(r['local_evidence']['local_inventory']['items']),
        'inventory_version':r['local_evidence']['local_inventory']['version']} for r in retrieval]
    (args.output_dir/'retrieval-preview.json').write_text(json.dumps(retrieval,ensure_ascii=False,indent=2))
    (args.output_dir/'pipeline-plan.json').write_text(json.dumps(preview,ensure_ascii=False,indent=2))
    for name in ('scout-prompt.txt','synthesis-prompt.txt','pipeline-plan.json','retrieval-preview.json'):
        os.chmod(args.output_dir/name,0o600)
    if not args.execute:
        print(f'Pipeline plan written to {args.output_dir}. No API calls.'); return
    values=read_environment(root/'.env')
    ledger=Path(values.get('TRIPPY_SHARED_BUDGET_LEDGER',str(root/'.local/stage3/extraction-budget.sqlite')))
    if not ledger.is_absolute(): ledger=root/ledger
    provider=AzureResearchProvider(values,ledger)
    result=run(brief,provider=provider,directory=args.output_dir,root=root,dataset=dataset,
        progress=lambda step,detail:print(f'{step}: {detail}'))
    print(f"Delivery: {result['delivery_status']}; {len(result['places'])} places; {len(result['plan_validation']['pending'])} pending checks.")

if __name__=='__main__': main()
