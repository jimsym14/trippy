"""Executable private integration campaign: checkpoints, drafts and honest gates."""
import argparse
from contextlib import closing
from copy import deepcopy
from datetime import datetime, timezone
import fcntl
import json
from pathlib import Path
import sqlite3
import time
from urllib.parse import urlsplit
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout

from trippy.planner.dataset_reader import compile_dataset, retrieve_activity, map_layers
from trippy.planner.draft import validate_trip, compose
from trippy.research.dataset_audit import audit
from trippy.sources.extraction import fingerprint
from trippy.sources.unattended import immutable_write, mutable_write

STAGES = ('audit', 'compile', 'retrieve', 'evidence', 'adjudicate', 'plan', 'evaluate')


class DeferredWork(RuntimeError):
    """A persisted provider cooldown exceeds this execution's time allowance."""


def read(path):
    return json.loads(Path(path).read_text())


def emit(message):
    print(datetime.now(timezone.utc).strftime('[%H:%M:%S UTC] ')+message, flush=True)


class Campaign:
    def __init__(self, root, manifest):
        self.folder = Path(root)/fingerprint(manifest)[:16]
        self.folder.mkdir(parents=True, exist_ok=True)
        immutable_write(self.folder/'manifest.json', manifest)
        self.db_path = self.folder/'queue.sqlite'
        with closing(sqlite3.connect(self.db_path)) as db:
            db.execute('CREATE TABLE IF NOT EXISTS stages(name TEXT PRIMARY KEY, state TEXT, output_sha TEXT, error TEXT)')
            db.execute('CREATE TABLE IF NOT EXISTS requests(id INTEGER PRIMARY KEY, host TEXT, at REAL)')
            db.execute('CREATE TABLE IF NOT EXISTS pages(id TEXT PRIMARY KEY, attempts INTEGER DEFAULT 0, state TEXT, retry_at REAL DEFAULT 0, output_sha TEXT, error TEXT)')
            db.execute('CREATE TABLE IF NOT EXISTS cooldowns(host TEXT PRIMARY KEY, until REAL)')
            db.commit()

    def stage(self, name, action):
        output = self.folder/(name+'.json')
        with closing(sqlite3.connect(self.db_path)) as db:
            row = db.execute('SELECT state,output_sha FROM stages WHERE name=?', (name,)).fetchone()
        if row and row[0] == 'succeeded':
            value = read(output)
            if fingerprint(value) != row[1]:
                raise ValueError('Checkpoint content differs: '+name)
            emit(name+': verified checkpoint')
            return value
        emit(name+': running')
        with closing(sqlite3.connect(self.db_path)) as db:
            db.execute('INSERT OR REPLACE INTO stages VALUES (?, ?, NULL, NULL)', (name, 'running')); db.commit()
        try:
            value = action()
            immutable_write(output, value)
            with closing(sqlite3.connect(self.db_path)) as db:
                db.execute('UPDATE stages SET state=?,output_sha=?,error=NULL WHERE name=?',
                           ('succeeded', fingerprint(value), name)); db.commit()
            return value
        except BaseException as exc:
            with closing(sqlite3.connect(self.db_path)) as db:
                db.execute('UPDATE stages SET state=?,error=? WHERE name=?', ('interrupted_or_failed', type(exc).__name__, name)); db.commit()
            mutable_write(self.folder/'status.json', {'state':'interrupted_or_failed', 'stage':name,
                'error':type(exc).__name__, 'resume_same_command':True, 'planner_ready':False})
            raise

    def reserve_http(self, domain, maximum):
        with closing(sqlite3.connect(self.db_path)) as db:
            db.execute('BEGIN IMMEDIATE')
            count = db.execute('SELECT COUNT(*) FROM requests').fetchone()[0]
            if count >= maximum:
                raise ValueError('HTTP request cap exhausted')
            db.execute('INSERT INTO requests(host,at) VALUES (?,?)', (domain,time.time())); db.commit()


def write_compiled_sqlite(path, compiled):
    """Deterministic projection plus full lineage payload, verified on every resume."""
    encoded = json.dumps(compiled, ensure_ascii=False, sort_keys=True)
    expected = [(p['id'], json.dumps(p,ensure_ascii=False,sort_keys=True)) for p in compiled['places']]
    path = Path(path)
    if not path.exists():
        temporary = path.with_suffix('.building')
        if temporary.exists(): temporary.unlink()
        with closing(sqlite3.connect(temporary)) as db:
            db.executescript('CREATE TABLE edition(sha TEXT PRIMARY KEY,document TEXT); CREATE TABLE places(id TEXT PRIMARY KEY,document TEXT);')
            db.execute('INSERT INTO edition VALUES (?,?)',(fingerprint(compiled),encoded))
            db.executemany('INSERT INTO places VALUES (?,?)', expected); db.commit()
        temporary.replace(path)
    with closing(sqlite3.connect(path.resolve().as_uri()+'?mode=ro',uri=True)) as db:
        if (db.execute('PRAGMA integrity_check').fetchone()[0]!='ok' or
            db.execute('SELECT sha,document FROM edition').fetchall()!=[(fingerprint(compiled),encoded)] or
            sorted(db.execute('SELECT * FROM places').fetchall())!=sorted(expected)):
            raise ValueError('Compiled SQLite content mismatch')


def evidence_jobs(campaign, compiled, retrieval, sources, connected, limits):
    from trippy.research.providers import fetch_operator, bounded_http_get
    from trippy.sources.luna import TransientProviderError
    packets = []
    selected = sorted({i['place_id'] for r in retrieval.values() for i in r['items']})[:limits['shortlist_source_occurrences']]
    indexed = {p['id']:p for p in compiled['places']}
    for key in selected:
        p = indexed[key]
        packets.append({'place_id':key, 'name':p['name'], 'source':p['source'],
            'needed':['canonical_branch_identity','selected_date_opening','route_if_scheduled'],
            'tags':p['tags'], 'details':p['details'], 'claims':p['record']['claims']})
    if not isinstance(sources,list) or len(sources)>limits['operator_pages']:
        raise ValueError('Bounded explicit operator source list required')
    for spec in sources:
        if not isinstance(spec,dict) or set(spec)!={'place_id','url'} or spec['place_id'] not in selected:
            raise ValueError('Operator source must bind to an actual shortlisted source occurrence')
    pages=[]; campaign_deadline=time.time()+limits['connected_wall_seconds']
    for spec in sources:
        key=fingerprint(spec); output=campaign.folder/'receipts'/(key+'.json')
        domain=urlsplit(spec['url']).hostname
        if not connected:
            pages.append({'spec':spec,'state':'deferred_offline'}); continue
        with closing(sqlite3.connect(campaign.db_path)) as db:
            db.execute('INSERT OR IGNORE INTO pages(id,state) VALUES (?,?)',(key,'queued'));db.commit()
            row=db.execute('SELECT attempts,state,retry_at,output_sha FROM pages WHERE id=?',(key,)).fetchone()
            cooldown=db.execute('SELECT until FROM cooldowns WHERE host=?',(domain,)).fetchone()
        if row[1]=='succeeded':
            value=read(output)
            if fingerprint(value)!=row[3]: raise ValueError('Operator receipt mismatch')
            pages.append({'spec':spec,'state':'observed_not_admitted','receipt':str(output)});continue
        if row[1] in {'review_required','attempts_exhausted'}:
            pages.append({'spec':spec,'state':row[1]});continue
        attempts, retry_at=row[0],max(row[2],cooldown[0] if cooldown else 0);state='attempts_exhausted'
        while attempts<limits['transient_attempts']:
            if retry_at>campaign_deadline or time.time()>campaign_deadline:
                state='deferred_retry_deadline';break
            while time.time()<retry_at:
                wait=min(15,max(0,retry_at-time.time()))
                emit('Provider cooldown; checkpoints saved; '+str(round(retry_at-time.time()))+'s remaining')
                time.sleep(wait)
            attempts+=1
            with closing(sqlite3.connect(campaign.db_path)) as db:
                db.execute('UPDATE pages SET attempts=?,state=? WHERE id=?',(attempts,'running',key));db.commit()
            emit('Operator page '+str(attempts)+'/'+str(limits['transient_attempts']))
            try:
                def hook(domain): campaign.reserve_http(domain,limits['http_requests'])
                def getter(url, **kwargs):
                    with ThreadPoolExecutor(max_workers=1) as pool:
                        task=pool.submit(bounded_http_get,url,request_hook=kwargs.get('request_hook'),deadline_seconds=60)
                        while True:
                            try:return task.result(timeout=15)
                            except FutureTimeout:emit('Waiting for bounded operator request; receipts and counters retained')
                value=fetch_operator(spec['url'],getter=getter,request_hook=hook)
                immutable_write(output,value)
                with closing(sqlite3.connect(campaign.db_path)) as db:
                    db.execute('UPDATE pages SET state=?,output_sha=? WHERE id=?',('succeeded',fingerprint(value),key));db.commit()
                state='observed_not_admitted';break
            except TransientProviderError as exc:
                delay=exc.retry_after_seconds
                retry_at=time.time()+(delay if delay is not None else min(60,15*2**(attempts-1)))
                with closing(sqlite3.connect(campaign.db_path)) as db:
                    db.execute('UPDATE pages SET state=?,retry_at=?,error=? WHERE id=?',('retry_wait',retry_at,exc.kind,key));db.commit()
                    db.execute('INSERT INTO cooldowns(host,until) VALUES (?,?) ON CONFLICT(host) DO UPDATE SET until=MAX(until,excluded.until)',
                               (domain,retry_at));db.commit()
                emit('Transient '+exc.kind+'; saved retry time')
            except (ValueError, OSError) as exc:
                state='review_required'
                with closing(sqlite3.connect(campaign.db_path)) as db:
                    db.execute('UPDATE pages SET state=?,error=? WHERE id=?',(state,type(exc).__name__,key));db.commit()
                break
        if state=='attempts_exhausted':
            with closing(sqlite3.connect(campaign.db_path)) as db:
                db.execute('UPDATE pages SET state=? WHERE id=?',(state,key));db.commit()
        pages.append({'spec':spec,'state':state,'receipt':str(output) if output.exists() else None})
    if any(p['state']=='deferred_retry_deadline' for p in pages):
        # Keep the stage resumable rather than freezing deferred jobs as complete.
        mutable_write(campaign.folder/'evidence-progress.json',{'operator_pages':pages})
        raise DeferredWork('Provider retry time retained; resume later with the same command')
    return {'shortlist_occurrences':selected,'research_packets':packets,'operator_pages':pages,
        'existing_operator_evidence':compiled['operational_evidence'],
        'existing_identity_evidence':compiled['identity_evidence'],
        'luna_calls':0,'paid_calls':0,
        'unsupported':['places_and_routes_adapters_not_connected','date_specific_availability','automatic_canonical_or_field_admission'],
        'note':'New pages remain observations for manual adjudication. No inferred identity joins.'}


def evaluate(compiled, before, golden):
    cases=[]
    for case in golden['cases']:
        expected=set(case['expected_source_ids'])
        after_ids={r['place_id'] for r in retrieve_activity(compiled,case['activity'],limit=100)['items']}
        before_ids={r['place_id'] for r in retrieve_activity(before,case['activity'],limit=100)['items']}
        precision=100*len(expected & after_ids)/len(after_ids) if after_ids else None
        recall=100*len(expected & after_ids)/len(expected) if expected else None
        cases.append({'activity':case['activity'],'expected':sorted(expected),'before':sorted(before_ids),'after':sorted(after_ids),
            'precision_percent':precision,'recall_percent':recall,'exact_expected_set':after_ids==expected,
            'coverage_gap':not after_ids,'review_scope':case['review_scope']})
    return {'cases':cases,'fixed_reviewed_sets_passed':all(c['exact_expected_set'] for c in cases),
        'scope':'Narrow reviewed source-recommendation benchmark, not whole-city accuracy or canonical place coverage',
        'overall_dataset_accuracy_percent':None}


def behavior_scenarios(compiled):
    """Exercise activity semantics on real data; missing supply remains a gap."""
    base={'synthetic':True,'start_date':'2030-01-10','end_date':'2030-01-12','activities':[]}
    variants=[
        ('baseline_without_optional_activities',{}),
        ('coffee_once',{'activities':[{'id':'coffee_break','frequency':'once'}]}),
        ('coffee_every_day',{'activities':[{'id':'coffee_break','frequency':'daily'}]}),
        ('coffee_merged_with_brunch',{'activities':[{'id':'coffee_break'},{'id':'brunch'}]}),
        ('breakfast_at_stay_provided',{'breakfast_at_stay':'provided'}),
        ('breakfast_at_stay_buy_supplies',{'breakfast_at_stay':'buy_supplies'}),
        ('breakfast_at_stay_unknown',{'breakfast_at_stay':'unknown'}),
        ('breakfast_out_bakery_or_cafe',{'activities':[{'id':'breakfast_out'}]}),
        ('groceries_map_layer',{}),('all_known_candidates_vs_according_to_plan',{'activities':[{'id':'coffee_break'}]}),
        ('low_budget_with_real_price_unknowns',{'budget_eur':10,'activities':[{'id':'coffee_break'}]}),
        ('dietary_hard_requirement_with_missing_evidence',{'hard_requirements':['dietary'],'activities':[{'id':'coffee_break'}]}),
        ('accessible_trip_with_missing_access_chain',{'hard_requirements':['accessibility'],'activities':[{'id':'coffee_break'}]}),
        ('user_locked_stop_and_local_replan',{}),('return_visit_with_exclusions',{}),('branch_conflict_moco_mood',{})]
    coffee=retrieve_activity(compiled,'coffee_break')['items']
    rows=[]
    for name,delta in variants:
        request={**base,**delta}
        if name=='return_visit_with_exclusions':request.update(activities=[{'id':'coffee_break'}],excluded_ids=[p['place_id'] for p in coffee])
        if name=='user_locked_stop_and_local_replan' and coffee:
            request.update(activities=[{'id':'coffee_break'}],locks=[{'place_id':coffee[0]['place_id'],
                'day':'2030-01-10','start_minute':600,'duration_minutes':60}])
        plan=compose(compiled,request);stops=[s for d in plan['days'] for s in d['stops']]
        checks={'no_window_errors':not plan['validation']['errors'],'no_dated_verification_claim':not plan['validation']['dated_checks_executed']}
        if name=='coffee_once':checks['frequency']=len([s for s in stops if 'coffee_break' in s['activities']])==(1 if coffee else 0)
        if name=='coffee_every_day':checks['frequency']=len([s for s in stops if 'coffee_break' in s['activities']])==(3 if coffee else 0)
        if name=='breakfast_at_stay_provided':checks['no_groceries']='groceries' not in plan['retrieval']
        if name=='breakfast_at_stay_buy_supplies':checks['supplies_requested']='groceries' in plan['retrieval']
        if name=='breakfast_at_stay_unknown':checks['unknown_visible']=all('stay_breakfast_provision_unknown' in d['stops'][0]['pending'] for d in plan['days'])
        if name=='low_budget_with_real_price_unknowns':checks['no_fake_total']=plan['budget']['known_total_eur'] is None
        if name in {'dietary_hard_requirement_with_missing_evidence','accessible_trip_with_missing_access_chain','return_visit_with_exclusions'}:
            checks['unsupported_stops_not_inserted']=not stops
        if name=='user_locked_stop_and_local_replan' and coffee:checks['lock_preserved']=any(s['locked'] and s['start_minute']==600 for s in stops)
        if name=='branch_conflict_moco_mood':checks['no_identity_promotion']=all(p['canonical_id'] is None for p in compiled['places'])
        rows.append({'id':name,'invariants':checks,'invariants_passed':all(checks.values()),
            'supply_gaps':[a for a,r in plan['retrieval'].items() if r['coverage_gap']],
            'pending_count':plan['validation']['pending_count'],
            'scope':'Synthetic activity behavior only; not full travel feasibility or branch adjudication'})
    return {'cases':rows,'passed':all(r['invariants_passed'] for r in rows),
            'full_personalized_itineraries_verified':0,'scope':'16 synthetic behavior cases, with supply gaps reported'}


def run(config_path, *, mode='offline', trip_path=None, sources_path=None, root=None, fail_after=None):
    config=read(config_path); selection=read(config['selection']);bundle=read(selection['dataset'])
    registry=read(config['registry']);migrations=read(config['taxonomy'])['migrations'];golden=read(config['golden'])
    if golden['edition_sha256']!=selection['bundle_sha256']:
        raise ValueError('Reviewed benchmark belongs to another edition')
    if config.get('paid_calls_enabled') is not False or config.get('automatic_publication') is not False:
        raise ValueError('This runner supports private, unpaid integration only')
    for name,maximum in [('shortlist_source_occurrences',60),('operator_pages',30),('http_requests',150),
                         ('connected_wall_seconds',43200),('transient_attempts',4)]:
        value=config['limits'][name]
        if type(value) is not int or not 0<value<=maximum:
            raise ValueError('Invalid execution limit: '+name)
    recipe=read(config['integration_recipe']);old=read(recipe['pack']);old_held=read(recipe['held'])
    trip=validate_trip(read(trip_path or config['demo_trip']),registry)
    sources=read(sources_path) if sources_path else []
    if mode not in {'offline','connected'}:raise ValueError('Invalid run mode')
    code_paths=[Path(__file__),Path('trippy/planner/dataset_reader.py'),Path('trippy/planner/draft.py'),
                Path('trippy/research/dataset_audit.py'),Path('trippy/research/dataset_integration.py'),Path('trippy/research/providers.py')]
    manifest={'version':1,'mode':mode,'config':config,'selection':selection,'trip':trip,'sources':sources,
        'inputs':{'bundle':fingerprint(bundle),'old':fingerprint(old),'old_held':fingerprint(old_held),
                  'registry':fingerprint(registry),'migrations':fingerprint(migrations),'golden':fingerprint(golden),
                  'recipe':fingerprint(recipe)},'engines':{str(p):fingerprint(p.read_text()) for p in code_paths}}
    root=Path(root or config['output_root']);root.mkdir(parents=True,exist_ok=True)
    campaign=Campaign(root,manifest)
    with (campaign.folder/'dispatch.lock').open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:raise ValueError('This campaign already has an active runner') from None
        mutable_write(root/'latest.json',{'campaign':str(campaign.folder),'manifest_sha256':fingerprint(manifest)})
        results={}
        def stage(name, action):
            results[name]=campaign.stage(name,action)
            if fail_after==name:
                mutable_write(campaign.folder/'status.json',{'state':'interrupted_for_test','stage':name,'planner_ready':False})
                raise RuntimeError('Injected interruption after '+name)
            return results[name]
        checked=stage('audit',lambda:audit(selection,recipe))
        def compile_stage():
            after=compile_dataset(bundle,migrations=migrations)
            historical={**bundle,'annotations':[]}
            before=compile_dataset(historical,pack=old,held=old_held)
            return {'after':after,'before':before}
        compiled=stage('compile',compile_stage)
        write_compiled_sqlite(campaign.folder/'compiled-dataset.sqlite',compiled['after'])
        activities=sorted({a['id'] for a in registry['activities']}|{'groceries'})
        retrieved=stage('retrieve',lambda:{'after':{a:retrieve_activity(compiled['after'],a) for a in activities},
                                         'before':{a:retrieve_activity(compiled['before'],a) for a in activities}})
        evidence=stage('evidence',lambda:evidence_jobs(campaign,compiled['after'],retrieved['after'],sources,
                                                       mode=='connected',config['limits']))
        adjudication=stage('adjudicate',lambda:{'existing_manual_annotations_applied':compiled['after']['metrics'],
            'new_operator_observations_admitted':0,'new_automatic_identity_approvals':0,
            'manual_handoff':[{'place_id':p['place_id'],'name':p['name'],'questions':p['needed'],
                'source':p['source'],'priority':'shortlisted_source_candidate'} for p in evidence['research_packets']],
            'coverage_gaps':[a for a,r in retrieved['after'].items() if r['coverage_gap']],
            'note':'Pending annotations are preserved. Source occurrence counts are not deduplicated unique places.'})
        plan=stage('plan',lambda:compose(compiled['after'],trip))
        def evaluate_stage():
            benchmark=evaluate(compiled['after'],compiled['before'],golden)
            scenarios=behavior_scenarios(compiled['after'])
            return {'audit_checks':checked['checks'],'benchmark':benchmark,'behavior_scenarios':scenarios,
                'source_admission_percent':checked['readiness']['after_percent'],
                'compiled_metrics':compiled['after']['metrics'],'draft_validation':plan['validation'],
                'gates':{'offline_audit_passed':all(checked['checks'].values()),
                    'retrieval_benchmark_passed':benchmark['fixed_reviewed_sets_passed'],
                    'draft_has_no_window_errors':not plan['validation']['errors'],
                    'activity_behavior_scenarios_passed':scenarios['passed'],
                    'selected_trip_checks_complete':False,'full_scenario_benchmark_complete':False,
                    'ui_contract_exported':True,'ui_rendering_validated':False,'publication_ready':False}}
        evaluation=stage('evaluate',evaluate_stage)
        immutable_write(campaign.folder/'trip-view.json',plan)
        immutable_write(campaign.folder/'map-layers.json',plan['map'])
        immutable_write(campaign.folder/'manual-handoff.json',adjudication)
        with closing(sqlite3.connect(campaign.db_path)) as db:
            requests=db.execute('SELECT COUNT(*) FROM requests').fetchone()[0]
        status={'campaign':str(campaign.folder),'state':'finished_with_explicit_handoffs','queue_drained':True,
                'gates':evaluation['gates'],'paid_calls':0,'luna_calls':0,'http_requests':requests,
                'active_dataset_changed':False,'planner_ready':False}
        mutable_write(campaign.folder/'status.json',status)
        report=render_report(checked,compiled['after'],adjudication,plan,evaluation,status)
        path=campaign.folder/'report.md'
        if path.exists() and path.read_text()!=report:raise ValueError('Immutable report differs')
        path.write_text(report)
        emit('Finished; report: '+str(path))
        return status


def render_report(checked,compiled,handoff,plan,evaluation,status):
    lines=['# Barcelona executable integration report','',
        'The runner completed the private integration stages. Remaining gates are explicit; this is not a city-wide or trip-date release.','',
        f"Source slots conserved: {checked['source_slots']}; editorial admission: {checked['readiness']['after_percent']}% (not accuracy).",
        f"Source occurrences: {compiled['metrics']['source_occurrences']}; admitted annotation items: {compiled['metrics']['admitted_annotation_items']}; content-bound taxonomy migrations: {compiled['metrics']['taxonomy_migrations_applied']}.",
        '', '| Activity | Expected source occurrences | Before | After | Exact reviewed set |',
        '| --- | ---: | ---: | ---: | --- |']
    for c in evaluation['benchmark']['cases']:
        lines.append(f"| {c['activity']} | {len(c['expected'])} | {len(c['before'])} | {len(c['after'])} | {c['exact_expected_set']} |")
    lines+=['','The benchmark is intentionally narrow. Empty groceries/brunch supply is a coverage gap, not a 100% success claim.',
        '',f"Draft validation: {plan['validation']['state']}; unresolved checks: {plan['validation']['pending_count']}.",
        'Ranking uses reviewed source matches and stable ordering. Geographic route fit and provider ratings are not implemented in this runner.',
        'No canonical deduplication or verified map pins were inferred. Existing operator/catalog links remain evidence, not approved transcript identities.',
        f"Synthetic behavior cases: {len(evaluation['behavior_scenarios']['cases'])}; invariants passed: {evaluation['behavior_scenarios']['passed']}. These are not complete travel feasibility checks.",
        '', '## Remaining work','',
        '- Resolve identities and branches for the actual shortlist; current fields and routes need capable providers.',
        '- Review only pending annotations relevant to selected activities. Do not rerun all video extraction.',
        '- Add Places/Routes adapters and selected-date checks before itinerary validation.',
        '- Complete full personalized itinerary benchmarks and visual UI verification; the 16 synthetic behavior cases and exports alone do not establish chat.md parity.',
        '', 'Coverage gaps: '+', '.join(handoff['coverage_gaps'])+'.',
        '', '## Run accounting','',
        f"Paid calls: 0; Luna calls: 0; physical HTTP requests: {status['http_requests']}.",
        'Checkpoints are hashed. Running the same command verifies/reuses successful stages. A new input or engine version creates a new campaign.',
        'The selected editorial dataset, prior receipts and shared AI ledger were not modified.','',
        'Gates:','', '```json',json.dumps(evaluation['gates'],indent=2),'```','']
    return '\n'.join(lines)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',nargs='?',default='offline',choices=['offline','connected','resume','status'])
    parser.add_argument('--config',default='configs/barcelona-finish-v1.json')
    parser.add_argument('--trip',type=Path);parser.add_argument('--sources',type=Path)
    args=parser.parse_args();config=read(args.config)
    if args.mode=='status':
        latest=read(Path(config['output_root'])/'latest.json');folder=Path(latest['campaign'])
        print(json.dumps(read(folder/'status.json') if (folder/'status.json').exists() else
            {'state':'in_progress_or_interrupted','campaign':str(folder)},indent=2));return
    if args.mode=='resume':
        if args.trip or args.sources:parser.error('Resume reuses frozen inputs; use offline/connected for changed inputs')
        manifest=read(Path(read(Path(config['output_root'])/'latest.json')['campaign'])/'manifest.json')
        # Explicit frozen input files reproduce the same campaign; engine/input changes cannot silently resume.
        frozen=Path(config['output_root'])/'resume-inputs'
        trip_path=frozen/(fingerprint(manifest['trip'])+'.json');immutable_write(trip_path,manifest['trip'])
        sources_path=frozen/(fingerprint(manifest['sources'])+'.json');immutable_write(sources_path,manifest['sources'])
        old_folder=read(Path(config['output_root'])/'latest.json')['campaign']
        # Before work, ensure the runner config and all code/data still bind to the manifest.
        if config!=manifest['config'] or any(fingerprint(Path(p).read_text())!=h for p,h in manifest['engines'].items()):
            raise ValueError('Inputs/engine changed; use a new offline or connected campaign')
        if read(config['selection'])!=manifest['selection']:
            raise ValueError('Selected edition changed; create a new campaign')
        selection=manifest['selection']
        inputs=manifest['inputs'];recipe=read(config['integration_recipe'])
        actual={'bundle':fingerprint(read(selection['dataset'])),'old':fingerprint(read(recipe['pack'])),
            'old_held':fingerprint(read(recipe['held'])),'registry':fingerprint(read(config['registry'])),
            'migrations':fingerprint(read(config['taxonomy'])['migrations']),'golden':fingerprint(read(config['golden'])),
            'recipe':fingerprint(recipe)}
        if actual!=inputs:raise ValueError('Frozen data changed; resume refused')
        result=run(args.config,mode=manifest['mode'],trip_path=trip_path,sources_path=sources_path)
        if result['campaign']!=old_folder:raise ValueError('Resume campaign mismatch')
    else:
        result=run(args.config,mode=args.mode,trip_path=args.trip,sources_path=args.sources)
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
