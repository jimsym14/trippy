"""Offline product benchmark with explicit gaps and scenario cost assumptions."""
import argparse
from collections import Counter
from copy import deepcopy
from datetime import date, timedelta
from decimal import Decimal
import json
import math
from pathlib import Path
import statistics
import time

from trippy.planner.dataset_reader import compile_dataset
from trippy.planner.draft import compose, validate_trip
from trippy.sources.extraction import fingerprint
from trippy.sources.unattended import immutable_write
from trippy_config import read_environment


def percentile(values, q):
    if not values:
        return None
    ordered=sorted(values);position=(len(ordered)-1)*q
    low=math.floor(position);high=math.ceil(position)
    return ordered[low]+(ordered[high]-ordered[low])*(position-low)


def token_cost(input_tokens, output_tokens, input_rate, output_rate):
    if any(type(n) is not int or n<0 for n in (input_tokens,output_tokens)):
        raise ValueError('Nonnegative token counts required')
    rates=[Decimal(str(r)) for r in (input_rate,output_rate)]
    if any(not r.is_finite() or r<0 for r in rates):
        raise ValueError('Finite nonnegative model rates required')
    return str((input_tokens*rates[0]+output_tokens*rates[1])/Decimal(1_000_000))


def future_cost(case, rates):
    """Explicit target architecture assumptions, not current model dispatch."""
    days=case['days'];gap_jobs=case['assumed_new_evidence_jobs']
    # Bound optional guide synthesis to three days / 8k output tokens per call.
    # Long trips repeat common input instead of being priced as one unlimited call.
    guide_calls=math.ceil(days/3)
    guide_input=12000*guide_calls+4000*days;guide_output=2000*guide_calls+2000*days
    total_input=guide_input+12000*gap_jobs;total_output=guide_output+2000*gap_jobs
    first=Decimal(token_cost(total_input,total_output,*rates))
    # Delta patch scenario: one 8k-input / 2k-output explanation job; not a measured cache hit.
    patch=token_cost(8000,2000,*rates)
    nplaces=case['assumed_unique_place_details'];nroutes=case['assumed_selected_route_edges']
    sensitivity=[]
    for unit in (Decimal('0'),Decimal('1'),Decimal('5'),Decimal('10')):
        provider=(nplaces+nroutes)*unit/Decimal(1000)
        sensitivity.append({'assumed_uniform_provider_usd_per_1000_requests':str(unit),
            'provider_cost_usd':str(provider),'model_plus_provider_usd':str(first+provider),
            'basis':'Sensitivity only; not a quote for any provider or SKU'})
    return {'assumed_model_calls':guide_calls+gap_jobs,'optional_guide_synthesis_calls':guide_calls,
        'guide_output_tokens_per_call_ceiling':8000,'input_tokens':total_input,'output_tokens':total_output,
        'cold_model_estimate_usd':str(first),'model_with_25_percent_token_allowance_usd':str(first*Decimal('1.25')),
        'local_reformat_or_filter_model_cost_usd':'0', 'one_targeted_ai_patch_model_estimate_usd':patch,
        'deterministic_guide_renderer_plus_gap_extraction_only_model_estimate_usd':token_cost(12000*gap_jobs,2000*gap_jobs,*rates),
        'place_detail_requests':nplaces,'route_edge_requests':nroutes,
        'places_quote_usd_per_1000':None,'routes_quote_usd_per_1000':None,
        'real_connected_total_usd':None,'sensitivity':sensitivity,
        'travel_spending_eur':None,
        'limits':'Optional rich guide synthesis/token/request counts are planning assumptions. A deterministic guide renderer can omit guide model calls. Cached-input discounts, retries, search/media and infrastructure are not included.'}


def historical_usage(path, rates):
    receipts={};duplicates=0;missing=0;invalid=0
    for line in Path(path).read_text().splitlines():
        value=json.loads(line);key=value.get('response_id')
        if not key:
            missing+=1;continue
        if key in receipts:
            duplicates+=1
            if value['usage']!=receipts[key]['usage']:
                raise ValueError('Conflicting historical usage receipts')
        else:receipts[key]=value
    totals=Counter();latencies=[];first_tokens=[]
    for value in receipts.values():
        usage=value.get('usage') or {}
        if any(type(usage.get(k)) is not int or usage[k]<0 for k in ('prompt_tokens','completion_tokens')):
            invalid+=1;continue
        totals['input']+=usage['prompt_tokens'];totals['output']+=usage['completion_tokens']
        totals['cached_input']+=(usage.get('prompt_tokens_details') or {}).get('cached_tokens',0) or 0
        totals['reasoning']+=(usage.get('completion_tokens_details') or {}).get('reasoning_tokens',0) or 0
        checkpoint=usage.get('latency_checkpoint') or {}
        elapsed=checkpoint.get('service_ttlt_ms');first=checkpoint.get('user_visible_ttft_ms')
        if type(elapsed) in {int,float} and elapsed>=0:latencies.append(elapsed)
        if type(first) in {int,float} and first>=0:first_tokens.append(first)
    return {'unique_response_receipts':len(receipts),'duplicates':duplicates,'missing_response_ids':missing,
        'invalid_usage':invalid,'models':dict(Counter(r.get('model') for r in receipts.values())),
        'input_tokens':totals['input'],'output_tokens':totals['output'],
        'reasoning_tokens_included_in_output_not_added_again':totals['reasoning'],
        'reported_cached_input_tokens':totals['cached_input'],
        'estimate_using_current_project_rates_usd':token_cost(totals['input'],totals['output'],*rates),
        'successful_response_full_latency_p50_ms':percentile(latencies,.50),
        'successful_response_full_latency_p95_ms':percentile(latencies,.95),
        'successful_response_first_token_p50_ms':percentile(first_tokens,.50),
        'scope':'All available project receipts, including extraction and reviews; not just the last campaign. Successful response latencies exclude retry/backoff and failed calls.',
        'azure_invoice_verified':False,
        'pricing_scope':'Estimate recalculated at current configured rates; not actual billed cost. Cached discounts not applied.'}


def inspect_output(plan, case):
    stops=[s for d in plan['days'] for s in d['stops']]
    selected=[s for s in stops if s['place_id'] is not None]
    fulfilment={}
    for activity in case['activities']:
        required=case['days'] if activity.get('frequency','once')=='daily' else 1
        actual=sum(activity['id'] in s['activities'] for s in stops)
        fulfilment[activity['id']]={'requested':required,'draft_occurrences':actual,
                                    'present_in_draft':actual>=required,'verified_service':False}
    unique={s['place_id'] for s in selected}
    empty_days=sum(not d['stops'] for d in plan['days'])
    minimum=case['minimum_stops_per_day']
    complete_days=sum(len(d['stops'])>=minimum for d in plan['days'])
    self_alternatives=sum(any(a['place_id']==s['place_id'] for a in s.get('alternatives',[])) for s in selected)
    cited=sum(bool(s.get('evidence')) for s in selected if not s['locked'])
    unsupported=case['required_future_capabilities']
    gaps=sorted(a for a,r in plan['retrieval'].items() if r['coverage_gap'])
    return {'days':len(plan['days']),'total_draft_stops':len(stops),'selected_source_occurrences':len(unique),
        'empty_days':empty_days,'minimum_stop_density_days':complete_days,
        'minimum_stop_density_percent':100*complete_days/len(plan['days']),
        'activity_fulfilment':fulfilment,'coverage_gaps':gaps,
        'selected_stops_with_evidence':cited,'self_as_alternative_errors':self_alternatives,
        'window_errors':plan['validation']['errors'],'pending_count':plan['validation']['pending_count'],
        'identity_confirmed_stops':0,'verified_map_pins':0,'route_checked_edges':0,
        'budget_complete':plan['budget']['cost_complete'],'media_references':sum(len(p['media']) for p in plan['panels']),
        'required_capabilities_not_implemented':unsupported,
        'full_usecase_acceptance':'not_ready' if unsupported or gaps or plan['validation']['pending_count'] or
            complete_days<len(plan['days']) or self_alternatives else 'draft_only_needs_manual_quality_review',
        'human_quality_score':None,
        'note':'Draft activity presence is not service verification. Stop density alone is not itinerary quality.'}


def run(config_path, repeats=5):
    if type(repeats) is not int or not 3<=repeats<=20:raise ValueError('Use 3 to 20 bounded repetitions')
    cfg=json.loads(Path(config_path).read_text());manifest=json.loads(Path(cfg['scenario_manifest']).read_text())
    selection=json.loads(Path(cfg['selection']).read_text());bundle=json.loads(Path(selection['dataset']).read_text())
    if fingerprint(bundle)!=selection['bundle_sha256']:raise ValueError('Selected dataset hash mismatch')
    registry=json.loads(Path(cfg['registry']).read_text())
    migrations=json.loads(Path(cfg['taxonomy']).read_text())['migrations']
    values=read_environment('.env')
    rates=(values.get('TRIPPY_LUNA_INPUT_PER_MILLION'),values.get('TRIPPY_LUNA_OUTPUT_PER_MILLION'))
    if None in rates:raise ValueError('Configured project model rates required')
    token_cost(0,0,*rates)
    compile_times=[];compiled=None
    for _ in range(3):
        started=time.perf_counter();compiled=compile_dataset(bundle,migrations=migrations)
        compile_times.append((time.perf_counter()-started)*1000)
    rows=[];all_times=[];start=date(2030,1,10)
    coffee=next((p['id'] for p in compiled['places'] if any(a['activity_id']=='coffee_break' for a in p['activities'])),None)
    for case in manifest['cases']:
        request={'synthetic':True,'start_date':start.isoformat(),
            'end_date':(start+timedelta(days=case['days']-1)).isoformat(),'activities':case['activities'],
            'hard_requirements':case.get('hard_requirements',[]),'locks':[],'excluded_ids':[],
            'budget_eur':case.get('travel_budget_eur')}
        if case.get('stay_breakfast'):request['breakfast_at_stay']=case['stay_breakfast']
        if case.get('exclude_coffee') and coffee:request['excluded_ids']=[coffee]
        if case.get('locked_stop') and coffee:
            request['locks']=[{'place_id':coffee,'day':start.isoformat(),'start_minute':600,'duration_minutes':60}]
        request=validate_trip(request,registry)
        measurements=[];plan=None
        for _ in range(repeats):
            started=time.perf_counter();plan=compose(compiled,request)
            # Include output serialization in the consumer latency measurement.
            encoded=json.dumps(plan,ensure_ascii=False,separators=(',',':')).encode()
            measurements.append((time.perf_counter()-started)*1000)
        all_times.extend(measurements)
        rows.append({'id':case['id'],'label':case['label'],'profile':case['profile'],'days':case['days'],
            'executed_supported_input_subset':request,
            'requested_output':case['requested_output'],
            'current':inspect_output(plan,case),'output_bytes':len(encoded),
            'latency_p50_ms':percentile(measurements,.50),'latency_p95_ms':percentile(measurements,.95),
            'measured_model_calls':0,'measured_provider_calls':0,'measured_external_cost_usd':'0',
            'future_architecture_cost_assumptions':future_cost(case,rates)})
    historical=historical_usage(cfg['usage_receipts'],rates)
    for row in rows:
        cost=row['future_architecture_cost_assumptions'];calls=cost['assumed_model_calls']
        cost['sequential_model_service_time_proxy_seconds']={
            'sum_of_historical_successful_call_medians':calls*historical['successful_response_full_latency_p50_ms']/1000,
            'sum_of_historical_successful_call_p95s':calls*historical['successful_response_full_latency_p95_ms']/1000,
            'basis':'Rough sequential-call sensitivity, not a measured end-to-end latency or statistical p95. Prompt sizes and workload differ; provider latency, queueing and retries are excluded.'}
    costs=[Decimal(r['future_architecture_cost_assumptions']['cold_model_estimate_usd']) for r in rows]
    report={'version':1,'dataset_sha256':fingerprint(bundle),'manifest_sha256':fingerprint(manifest),
        'benchmark_engine_sha256':fingerprint(Path(__file__).read_text()),
        'consumer_engine_sha256':fingerprint(Path('trippy/planner/draft.py').read_text()),
        'reader_engine_sha256':fingerprint(Path('trippy/planner/dataset_reader.py').read_text()),
        'pricing':{'input_usd_per_million':rates[0],'output_usd_per_million':rates[1],
            'basis':'Existing local project configured rates, not a verified Azure invoice',
            'official_openai_reference':cfg['official_pricing_reference']},
        'scenario_count':len(rows),'repetitions_per_case':repeats,'consumer_runs':len(all_times),
        'compile_cpu_p50_ms':percentile(compile_times,.50),'compile_cpu_p95_ms':percentile(compile_times,.95),
        'warm_consumer_p50_ms':percentile(all_times,.50),'warm_consumer_p95_ms':percentile(all_times,.95),
        'cold_model_estimate_min_usd':str(min(costs)),'cold_model_estimate_max_usd':str(max(costs)),
        'one_run_each_case_model_estimate_usd':str(sum(costs)),
        'maximum_token_allowance_for_one_run_each_case_usd':str(sum(costs)*Decimal('1.25')),
        'model_only_traffic_sensitivity':[
            {'trips':n,'assumed_equal_mix_of_32_profiles':True,
             'model_estimate_usd':str(sum(costs)*Decimal(n)/Decimal(len(rows))),
             'model_estimate_with_25_percent_token_allowance_usd':str(sum(costs)*Decimal(n)/Decimal(len(rows))*Decimal('1.25')),
             'provider_and_infrastructure_cost_usd':None}
            for n in (100,1000,10000)],
        'actual_external_benchmark_cost_usd':'0','historical_usage':historical,'cases':rows,
        'quality_rubric':manifest['quality_rubric'],
        'scope':'Measured offline partial consumer, scenario assumptions for future connected output. Not an executed full-itinerary or live-provider benchmark.'}
    output=Path(cfg['output_root'])/fingerprint(report)[:16]
    immutable_write(output/'benchmark.json',report)
    markdown=render(report)
    path=output/'report.md';path.write_text(markdown)
    # The benchmark timings naturally differ between executions; each result is a distinct edition.
    immutable_write(output/'scenarios.json',manifest)
    print(json.dumps({'report':str(path),'benchmark':str(output/'benchmark.json'),
        'scenario_count':len(rows),'runs':len(all_times),
        'warm_p50_ms':report['warm_consumer_p50_ms'],'warm_p95_ms':report['warm_consumer_p95_ms'],
        'cold_model_estimate_range_usd':[str(min(costs)),str(max(costs))],
        'one_run_each_case_estimate_usd':str(sum(costs)),
        'historical_estimate_usd':historical['estimate_using_current_project_rates_usd'],
        'full_usecases_ready':sum(r['current']['full_usecase_acceptance']!='not_ready' for r in rows),
        'actual_external_cost_usd':'0'},indent=2))
    return report,output


def render(report):
    lines=['# Barcelona cost, performance and output benchmark','',report['scope'],'',
        f"Cases: {report['scenario_count']}; offline consumer runs: {report['consumer_runs']}; external cost: $0.",
        f"Warm consumer + JSON p50: {report['warm_consumer_p50_ms']:.2f}ms; p95: {report['warm_consumer_p95_ms']:.2f}ms.",
        f"Compile CPU p50: {report['compile_cpu_p50_ms']:.2f}ms. These timings exclude UI, network, full planner and process startup.",
        '', '| Case | Days | Draft stops | Gaps | p50 ms | JSON KB | Future model USD | Full case |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |']
    for row in report['cases']:
        lines.append(f"| {row['label']} | {row['days']} | {row['current']['total_draft_stops']} | {len(row['current']['coverage_gaps'])} | {row['latency_p50_ms']:.2f} | {row['output_bytes']/1024:.1f} | {row['future_architecture_cost_assumptions']['cold_model_estimate_usd']} | {row['current']['full_usecase_acceptance']} |")
    h=report['historical_usage']
    lines+=['','## Interpretation','',
        'All scenarios are run through the supported contract subset. Unsupported party, full-day, route, rating, booking and detailed dietary requirements are explicitly listed per case and are not treated as implemented.',
        'The future model column is a token-budget estimate for a proposed connected architecture, not measured output quality or a live call.',
        f"Configured model rates: ${report['pricing']['input_usd_per_million']} input / ${report['pricing']['output_usd_per_million']} output per 1M tokens.",
        f"Future model estimate for one run of every case: ${report['one_run_each_case_model_estimate_usd']}; with 25% token allowance: ${report['maximum_token_allowance_for_one_run_each_case_usd']}.",
        'Provider unit rates and the real connected total remain unknown. Per-case $0/$1/$5/$10 per 1,000-request sensitivity values are assumptions, not provider quotes. Infrastructure, search/media and retries are separate.',
        'Local filtering/reformatting should require no model call. One targeted 8k-input/2k-output AI patch is priced independently, without claiming a cached-token discount.',
        '', '## Historical receipts','',
        f"Unique receipts: {h['unique_response_receipts']}; input: {h['input_tokens']}; output: {h['output_tokens']} tokens.",
        f"Recalculated estimate at configured rates: ${h['estimate_using_current_project_rates_usd']}; Azure invoice unverified.",
        f"Successful response service latency p50: {h['successful_response_full_latency_p50_ms']}ms; p95: {h['successful_response_full_latency_p95_ms']}ms. Retry/backoff and failures are excluded.",
        '', '## Output quality gates','',
        'Human review is required for relevance, source-detail usefulness, geographical sequence and guide completeness. No automated score is invented for these dimensions.',
        'Source attribution, explicit unknowns, locks/exclusions and window checks can be evaluated automatically. Full acceptance also needs complete days, usable identities/locations, route-backed transfers, budget ranges and rendered UI.',
        '', 'Full scenario input profiles, required outputs, current gaps, pricing formulas and sensitivities are in benchmark.json and scenarios.json.','']
    return '\n'.join(lines)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',default='configs/barcelona-product-benchmark-v1.json')
    parser.add_argument('--repeats',type=int,default=5)
    args=parser.parse_args();run(args.config,args.repeats)


if __name__=='__main__':main()
