"""Run a prepared, bounded Luna pilot and write private review artifacts.

Default is offline cost preparation. Paid execution requires the existing
environment guard, cap and deployment rates. No catalog publication or browsing.
"""
import argparse
from collections import Counter
from decimal import Decimal
import json
from pathlib import Path

from trippy_config import read_environment
from .extraction import Extraction, prompt_for_version, aggregate, execute_chunks, fingerprint
from .luna import BudgetError, make_provider, positive


def validate_pilot(document):
    chunks=document.get('chunks',[])
    if document.get('version')!=1 or not 1<=len(chunks)<=6 or document.get('planned_calls')!=len(chunks):
        raise ValueError('Expected a prepared pilot with at most six calls')
    if len({c['id'] for c in chunks})!=len(chunks):raise ValueError('Duplicate chunk IDs')
    schema=Extraction.model_json_schema()
    for chunk in chunks:
        prompt=prompt_for_version(chunk.get('prompt_version')).read_text()
        if chunk['system_prompt']!=prompt or chunk['response_schema']!=schema:
            raise ValueError('Prepared prompt/schema no longer matches current extractor')
        if chunk['id']!=fingerprint({'prompt':prompt,'schema':schema,'payload':chunk['payload']}):
            raise ValueError('Prepared request fingerprint mismatch')
    return chunks


def cost_preview(chunks,values,max_attempts=2):
    if type(max_attempts) is not int or not 1<=max_attempts<=3:raise ValueError('Invalid retry cap')
    output_tokens=int(values.get('TRIPPY_LUNA_MAX_OUTPUT_TOKENS','8000'))
    input_allowance=0
    for chunk in chunks:
        messages=[{'role':'system','content':chunk['system_prompt']},
                  {'role':'user','content':json.dumps(chunk['payload'],ensure_ascii=False)}]
        input_allowance+=len(json.dumps(messages,ensure_ascii=False).encode())+len(json.dumps(chunk['response_schema']).encode())+4096
    summary={'planned_calls':len(chunks),'maximum_attempts':len(chunks)*max_attempts,
        'input_token_reservation_allowance':input_allowance,'output_token_reservation_allowance':output_tokens*len(chunks),
        'pricing_status':'deployment_rates_missing','catalog_writes':0}
    if values.get('TRIPPY_LUNA_INPUT_PER_MILLION') and values.get('TRIPPY_LUNA_OUTPUT_PER_MILLION'):
        input_rate=positive(values['TRIPPY_LUNA_INPUT_PER_MILLION'],'TRIPPY_LUNA_INPUT_PER_MILLION')
        output_rate=positive(values['TRIPPY_LUNA_OUTPUT_PER_MILLION'],'TRIPPY_LUNA_OUTPUT_PER_MILLION')
        reserved=(input_allowance*input_rate+output_tokens*len(chunks)*output_rate)/Decimal(1_000_000)
        summary.update(pricing_status='configured_reservation_rates',currency=values.get('TRIPPY_AI_BUDGET_CURRENCY'),
            one_attempt_reservation=str(reserved),maximum_retry_reservation=str(reserved*max_attempts))
    return summary


def run_pilot(document,values,output,*,execute=False,catalog=None,cache_dir=None,budget_ledger=None,max_attempts=2):
    chunks=validate_pilot(document)
    output=Path(output)
    if output.exists():raise ValueError('Choose a new pilot output path')
    preview=cost_preview(chunks,values,max_attempts)
    output.parent.mkdir(parents=True,exist_ok=True)
    # Reserve the report before paid activity, leaving recoverable status on failure.
    with output.open('x') as stream:json.dump({'version':1,'status':'pilot_preparing','cost_preview':preview},stream)
    if not execute:
        report={'version':1,'status':'pilot_prepared_not_executed','cost_preview':preview,'paid_calls':0,'catalog_writes':0}
    else:
        ledger=Path(budget_ledger or '.local/stage3/extraction-budget.sqlite')
        ledger.parent.mkdir(parents=True,exist_ok=True)
        try:provider=make_provider(values,ledger)
        except BudgetError as exc:
            output.write_text(json.dumps({'version':1,'status':'pilot_blocked_configuration',
                'reason':str(exc),'cost_preview':preview,'paid_calls':0,'catalog_writes':0},indent=2))
            raise
        results,errors=execute_chunks(chunks,provider,cache_dir or '.local/stage3/extraction-cache',max_attempts=max_attempts)
        report=aggregate(results,catalog)
        report.update(cost_preview=preview,completed_chunk_ids=[c['id'] for c,_ in results],failed_chunks=errors,
            execution_status='partial' if errors else 'complete',
            summary={'completed_chunks':len(results),'planned_chunks':len(chunks),
                'mentions':len(report['drafts']),
                'by_category':dict(Counter(category for draft in report['drafts'] for category in draft['categories'])),
                'uncertain_identity_mentions':sum(d['identity_uncertain'] for d in report['drafts']),
                'unmatched_venue_mentions':sum(d['kind']=='venue' and not d['identity_candidates'] for d in report['drafts'])},
            review_required=['source-quote meaning and unsupported claims','category fidelity and missing details',
                'multilingual venue identities and branches','current operational facts before planning'])
    temporary=output.with_name(output.name+'.tmp')
    temporary.write_text(json.dumps(report,ensure_ascii=False,indent=2));temporary.replace(output)
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--prepared',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--env-file',type=Path,default=Path('.env'))
    p.add_argument('--execute-luna',action='store_true')
    p.add_argument('--catalog',type=Path,default=Path('.local/catalog.sqlite'))
    p.add_argument('--cache-dir',type=Path,default=Path('.local/stage3/extraction-cache'))
    p.add_argument('--budget-ledger',type=Path,default=Path('.local/stage3/extraction-budget.sqlite'))
    args=p.parse_args()
    report=run_pilot(json.loads(args.prepared.read_text()),read_environment(args.env_file),args.output,
        execute=args.execute_luna,catalog=args.catalog,cache_dir=args.cache_dir,budget_ledger=args.budget_ledger)
    print(json.dumps({'status':report['status'],'execution_status':report.get('execution_status'),
        'cost_preview':report['cost_preview'],'summary':report.get('summary')}))


if __name__=='__main__':main()
