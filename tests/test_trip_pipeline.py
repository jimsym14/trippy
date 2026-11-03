import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from trippy.planner.planning_contract import empty_batch, normalized_brief, validate_batch
from trippy.planner.plan_engine import compose_plan, merge_batches, requirement_supported
from trippy.planner.pipeline import StageStore, run, task_matrix
from trippy.planner.research_context import selected_dataset, task_context

BRIEF={'destination':'Barcelona','date_range':{'arrival':'2026-12-05','departure':'2026-12-06'},
       'interests':['sights','food'],'travelers':{'count':4},'pace':'balanced'}
EMPTY_DATASET={'state':'not_available','version':None,'candidates':[],'context':[],'operational':{},'coverage':{}}


def source(): return {'id':'S1','url':'https://example.org/official','publisher':'Synthetic operator','type':'primary','checked_at':'2026-11-02'}


def place(number, category='attraction'):
    return {'id':f'p{number}','name':f'Synthetic place {number}','category':category,
        'description':'Synthetic fixture, never a real venue claim','why_recommended':'Fixture match',
        'address':f'Fixture street {number}','official_url':'https://example.org/official','source_ids':['S1'],
        'coordinates':{'latitude':41.38+number*.001,'longitude':2.17,'source_ids':['S1']},
        'identity_status':'source_matched','tags':[],
        'cuisine':None,'dietary_options':[],'best_for':[],'best_time':None,'reservation_required':None,
        'image_url':None,'image_source_url':None,'image_attribution':None,
        'rating':{'value':None,'scale':None,'platform':None,'review_count':None},
        'price':{'min':10,'max':10,'currency':'EUR','basis':'adult_standard'},'price_source_ids':['S1'],
        'average_visit_minutes':60,'duration_basis':'estimate'}


def batch(n=10):
    b=empty_batch(); b['sources']=[source()]; b['places']=[place(i,'food' if i%2 else 'attraction') for i in range(n)]
    b['date_checks']=[{'entity_id':p['id'],'local_date':d,'status':'confirmed',
       'opening_windows':[{'start':'09:00','end':'23:00'}], 'details':'Fixture only','source_ids':['S1'],'checked_at':'2026-11-02'}
       for p in b['places'] for d in ['2026-12-05','2026-12-06']]
    b['calendar_checks']=[{'date':d,'status':'researched','details':'Fixture','source_ids':['S1'],'checked_at':'2026-11-02'} for d in ['2026-12-05','2026-12-06']]
    b['transport_options']=[{'id':'T1','name':'Fixture transit','best_for':'Fixture','price':{'min':None,'max':None,'currency':'EUR','basis':'unknown'},
        'official_url':'https://example.org/official','source_ids':['S1'],'limitations':[]}]
    b['ticket_options']=[{'id':'K1','place_id':'p0','name':'Fixture ticket','price_per_person_eur':10,'group_price_eur':None,
        'booking_url':'https://example.org/official','notes':'Adult standard, not a family quote','source_ids':['S1']}]
    return b


class RecordedProvider:
    def __init__(self): self.calls=[]
    def research(self,prompt,task_id):
        self.calls.append(('research',task_id))
        return {'text':'Fixture https://example.org/official','citation_urls':['https://example.org/official']}
    def normalize(self,system,payload,schema,task_id):
        self.calls.append(('normalize',task_id)); return batch()


class TripPipelineTests(unittest.TestCase):
    def test_schema_rejects_wrong_fields_and_bool_price(self):
        validate_batch(batch())
        b=batch(); b['places'][0]['price']['min']=True
        with self.assertRaises(ValueError): validate_batch(b)
        b=batch(); b['places'][0]['extra']='silent field'
        with self.assertRaises(ValueError): validate_batch(b)

    def test_preserves_brief_preferences_and_locks(self):
        brief=normalized_brief({**BRIEF,'custom_instructions':'Keep my note','dietary_needs':['Vegan'],'stay_style':'Boutique'})
        self.assertEqual(brief['custom_instructions'],'Keep my note')
        self.assertEqual(brief['dietary_needs'],['Vegan'])
        self.assertEqual(brief['stay_style'],'Boutique')
        self.assertGreater(len(task_matrix(brief)),2)
        self.assertIn('logistics',[t['kind'] for t in task_matrix(brief)])

    def test_merge_stable_ids_deduplicates_sources_and_branches(self):
        brief=normalized_brief(BRIEF); b=batch()
        doc=merge_batches([b,copy.deepcopy(b)],brief)
        self.assertEqual(len(doc['places']),10); self.assertEqual(len(doc['sources']),1)
        extra=copy.deepcopy(b); extra['places'][0]['address']='Different branch'
        doc=merge_batches([b,extra],brief)
        self.assertEqual(len(doc['places']),11)
        self.assertEqual({c['entity_id'] for c in doc['date_checks']},{p['id'] for p in doc['places']})

    def test_provenance_is_required_for_coordinates_and_prices(self):
        for field in ['coordinates','price_source_ids']:
            b=batch()
            if field=='coordinates': b['places'][0][field]['source_ids']=[]
            else: b['places'][0][field]=[]
            with self.subTest(field=field),self.assertRaises(ValueError): merge_batches([b],normalized_brief(BRIEF))

    def test_missing_coordinate_ambiguous_and_closed_are_not_scheduled(self):
        b=batch(); b['places'][0]['coordinates']={'latitude':None,'longitude':None,'source_ids':[]}
        b['places'][1]['identity_status']='ambiguous'
        for c in b['date_checks']:
            if c['entity_id']=='p2': c['status']='closed'; c['opening_windows']=[]
        brief=normalized_brief(BRIEF); doc=merge_batches([b],brief); result=compose_plan(doc,brief)
        scheduled={s['activity'] for d in result['itinerary']['days'] for s in d['stops']}
        self.assertFalse({'Synthetic place 0','Synthetic place 1','Synthetic place 2'} & scheduled)
        self.assertEqual(result['delivery_status'],'partial')

    def test_constraints_exclusions_and_unknown_are_not_false(self):
        brief=normalized_brief({**BRIEF,'dietary_needs':['No nuts']}); b=batch()
        doc=merge_batches([b],brief); p=next(p for p in doc['places'] if p['category']=='attraction')
        brief['excluded_place_ids']=[p['id']]
        result=compose_plan(doc,brief)
        selected={s['place_id'] for d in result['itinerary']['days'] for s in d['stops']}
        self.assertNotIn(p['id'],selected)
        selected_places={q['id']:q for q in doc['places']}
        self.assertTrue(all(selected_places[x]['category']!='food' for x in selected))

    def test_schedule_diversity_order_and_routes_are_deterministic(self):
        brief=normalized_brief(BRIEF); doc=merge_batches([batch()],brief)
        first=compose_plan(doc,brief); second=compose_plan(doc,brief)
        self.assertEqual(first,second)
        stops=[s for d in first['itinerary']['days'] for s in d['stops']]
        self.assertTrue(stops); self.assertEqual(len(stops),len({s['place_id'] for s in stops}))
        for d in first['itinerary']['days']:
            self.assertEqual([s['time'] for s in d['stops']],sorted(s['time'] for s in d['stops']))
        adjacent={(a['place_id'],b['place_id'],d['date']) for d in first['itinerary']['days'] for a,b in zip(d['stops'],d['stops'][1:])}
        self.assertTrue(all((r['from_place_id'],r['to_place_id'],r['date']) in adjacent for r in first['route_previews']))
        self.assertTrue(all(not r['verified'] for r in first['route_previews']))

    def test_locked_stops_survive_and_conflicts_are_reported(self):
        brief=normalized_brief(BRIEF); doc=merge_batches([batch()],brief)
        p=doc['places'][0]
        brief['locked_stops']=[{'place_id':p['id'],'date':'2026-12-05','time':'10:00','duration_minutes':120}]
        for c in doc['date_checks']:
            if c['entity_id']==p['id']: c['status']='closed'
        result=compose_plan(doc,brief)
        self.assertTrue(any(s.get('locked') and s['time']=='10:00' for s in result['itinerary']['days'][0]['stops']))
        self.assertIn('locked_place_closed',[x['code'] for x in result['plan_validation']['pending']])

    def test_money_is_derived_only_from_scheduled_known_prices(self):
        brief=normalized_brief(BRIEF); b=batch()
        for p in b['places']: p['price']={'min':0,'max':0,'currency':'EUR','basis':'adult_standard'}
        result=compose_plan(merge_batches([b],brief),brief)
        self.assertEqual(result['costs']['known_scheduled_price_subtotal']['min'],0)
        self.assertIsNone(result['costs']['known_scheduled_price_subtotal']['group_total_eur'])
        self.assertIsNone(result['costs']['per_person_estimate']['min'])
        b['places'][0]['price']={'min':None,'max':None,'currency':'EUR','basis':'adult_standard'}
        result=compose_plan(merge_batches([b],brief),brief)
        self.assertIsNone(result['costs']['per_person_estimate']['min'])

    def test_resume_reuses_success_and_never_redispatches_uncertain_stage(self):
        with tempfile.TemporaryDirectory() as folder:
            store=StageStore(folder); calls=[]
            self.assertEqual(store.run('one',{'a':1},lambda:calls.append(1) or {'ok':1}),{'ok':1})
            store.run('one',{'a':1},lambda:self.fail('Repeated dispatch'))
            self.assertEqual(calls,[1])
            with self.assertRaises(ValueError): store.run('one',{'a':2},lambda:None)
            with self.assertRaises(TimeoutError): store.run('two',{},lambda:(_ for _ in ()).throw(TimeoutError()))
            with self.assertRaises(ValueError): store.run('two',{},lambda:self.fail('Unknown spend dispatched again'))

    def test_full_pipeline_produces_app_projection_and_resumes_without_calls(self):
        with tempfile.TemporaryDirectory() as folder:
            provider=RecordedProvider()
            first=run(BRIEF,provider=provider,directory=folder,root=folder,dataset=EMPTY_DATASET)
            calls=provider.calls.copy()
            second=run(BRIEF,provider=provider,directory=folder,root=folder,dataset=EMPTY_DATASET)
            self.assertEqual(first,second); self.assertEqual(calls,provider.calls)
            self.assertTrue(first['itinerary']['days'][0]['stops'])
            self.assertTrue(first['map_views']); self.assertTrue(first['plan_validation']['pending'])
            self.assertTrue((Path(folder)/'trippy-research.json').is_file())

    def test_failure_keeps_prior_evidence_without_automatic_retry(self):
        provider=RecordedProvider(); research=provider.research
        def fail_second(prompt,task_id):
            if provider.calls: raise TimeoutError('synthetic')
            return research(prompt,task_id)
        provider.research=fail_second
        with tempfile.TemporaryDirectory() as folder:
            result=run(BRIEF,provider=provider,directory=folder,root=folder,dataset=EMPTY_DATASET)
            self.assertEqual(result['delivery_status'],'partial')
            self.assertEqual(len(result['pipeline_report']['failed_stages']),1)
            self.assertTrue(result['places'])
            self.assertEqual(len(provider.calls),2)

    def test_source_invention_is_rejected(self):
        provider=RecordedProvider()
        provider.research=lambda *_:{'text':'No URLs supplied','citation_urls':[]}
        with tempfile.TemporaryDirectory() as folder:
            result=run(BRIEF,provider=provider,directory=folder,root=folder,dataset=EMPTY_DATASET)
            self.assertFalse(result['places']); self.assertEqual(result['delivery_status'],'partial')

    def test_real_selected_edition_is_read_only_research_context(self):
        root=Path(__file__).resolve().parents[1]
        pointer=root/'.local/stage3/planner-release-v1/active-dataset.json'
        if not pointer.is_file(): self.skipTest('Local editorial edition absent')
        dataset=selected_dataset(root,'Barcelona')
        self.assertTrue(dataset['candidates']); self.assertFalse(dataset['planner_ready'])
        self.assertTrue(all(p['status'].startswith('editorial_source_context') for p in dataset['candidates']))

if __name__=='__main__': unittest.main()


class TripPipelineRegressionTests(unittest.TestCase):
    def test_exact_branch_retains_user_identity(self):
        brief=normalized_brief({**BRIEF,'existing_places':[{'id':'user-place','name':'Synthetic place 0','address':'Fixture street 0'}]})
        doc=merge_batches([batch()],brief)
        self.assertIn('user-place',{p['id'] for p in doc['places']})
        self.assertTrue(any(c['entity_id']=='user-place' for c in doc['date_checks']))
        b=batch();b['places'][0]['address']='Different street'
        self.assertNotIn('user-place',{p['id'] for p in merge_batches([b],brief)['places']})

    def test_conflicts_survive_third_response(self):
        for field in ('coordinates','date_checks','opening_windows'):
            first=batch();second=batch();third=batch()
            if field=='coordinates': second['places'][0]['coordinates']['latitude']+=.05
            elif field=='date_checks': second['date_checks'][0]['status']='closed'
            else: second['date_checks'][0]['opening_windows']=[{'start':'14:00','end':'18:00'}]
            doc=merge_batches([first,second,third],normalized_brief(BRIEF))
            pid=next(p['id'] for p in doc['places'] if p['name']=='Synthetic place 0')
            with self.subTest(field=field):
                if field=='coordinates': self.assertEqual(next(p['identity_status'] for p in doc['places'] if p['id']==pid),'ambiguous')
                else: self.assertEqual(next(c['status'] for c in doc['date_checks'] if c['entity_id']==pid and c['local_date']=='2026-12-05'),'candidate')

    def test_contradictory_hard_checks_are_not_supported(self):
        b=batch();b['constraint_checks']=[{'entity_id':'p1','requirement':'Vegan','local_date':'2026-12-05','status':status,'source_ids':['S1'],'checked_at':'2026-11-02'} for status in ('supported','unsupported')]
        doc=merge_batches([b],normalized_brief(BRIEF));pid=next(p['id'] for p in doc['places'] if p['name']=='Synthetic place 1')
        self.assertFalse(requirement_supported(doc,pid,'vegan','2026-12-05'))

    def test_route_provider_failure_and_missing_locked_pin(self):
        brief=normalized_brief(BRIEF);doc=merge_batches([batch()],brief)
        def fail(*args): raise TimeoutError('fixture')
        result=compose_plan(doc,brief,route_provider=fail)
        self.assertTrue(result['route_previews']);self.assertTrue(all(not r['verified'] for r in result['route_previews']))
        doc['places'][0]['coordinates']={'latitude':None,'longitude':None,'source_ids':[]}
        brief['locked_stops']=[{'place_id':doc['places'][0]['id'],'date':'2026-12-05','time':'08:00','duration_minutes':60}]
        result=compose_plan(doc,brief)
        self.assertIn('identity_or_coordinates_pending',[p['code'] for p in result['plan_validation']['pending']])

    def test_operational_context_matches_exact_subject(self):
        dataset={**EMPTY_DATASET,'operational':{'prose_proposals':[{'subject_name':'A','subject_address':'Street 1','source_url':'https://example.org/a'}, {'subject_name':'A','subject_address':'Street 2'}]}}
        task={'kind':'selected_checks','categories':[],'places':[{'name':'A','address':'Street 1'}]}
        context=task_context(dataset,task,normalized_brief(BRIEF))
        self.assertEqual(len(context['operational_observations']['prose_proposals']),1)


class BridgeIsolationTests(unittest.TestCase):
    def setUp(self):
        import bridge_server
        self.bridge=bridge_server; self.folder=tempfile.TemporaryDirectory()
        self.root_patch=patch.object(bridge_server,'root',return_value=Path(self.folder.name));self.root_patch.start()
        self.state_patch=patch.object(bridge_server,'state',bridge_server.ResearchState());self.state_patch.start()
    def tearDown(self):
        self.state_patch.stop();self.root_patch.stop();self.folder.cleanup()
    def test_atomic_begin_gate_and_restart(self):
        import concurrent.futures
        def begin():
            try: return self.bridge.begin_job(BRIEF)[0]
            except RuntimeError: return None
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: jobs=list(pool.map(lambda _:begin(),range(4)))
        self.assertEqual(sum(j is not None for j in jobs),1)
        job=next(j for j in jobs if j)
        self.bridge.state=self.bridge.ResearchState()
        restored=self.bridge.read_job(job)
        self.assertFalse(restored['is_running']);self.assertEqual(restored['step'],'interrupted')
    def test_preflight_and_unknown_job_expose_no_private_result(self):
        from uuid import uuid4
        self.bridge.begin_job({**BRIEF,'custom_instructions':'private fixture'})
        def get(path):
            handler=object.__new__(self.bridge.RequestHandler);handler.path=path
            reply=[];handler.send_json=lambda status,payload:reply.append((status,payload))
            handler.do_GET();return reply[0]
        status,payload=get('/api/status')
        self.assertEqual(status,200)
        self.assertFalse({'request_context','result','job_id'} & payload.keys())
        self.assertEqual(get('/api/status?job_id='+str(uuid4()))[0],404)
        self.assertEqual(get('/api/status?job_id=../../secret')[0],404)
    def test_completed_runs_remain_separate(self):
        jobs=[]
        for destination in ('Barcelona','Athens'):
            job,brief=self.bridge.begin_job({**BRIEF,'destination':destination})
            self.bridge.run_pipeline(brief,job,provider=RecordedProvider())
            jobs.append(job)
        for job,destination in zip(jobs,('Barcelona','Athens')):
            self.assertEqual(self.bridge.read_job(job)['result']['trip_context']['destination'],destination)
        self.assertNotEqual(jobs[0],jobs[1])


class ContextCoverageRegressionTests(unittest.TestCase):
    def test_pages_use_distinct_editorial_context(self):
        dataset={**EMPTY_DATASET,'candidates':[{'name':f'Place {i:02d}','record_id':str(i),'categories':['food'],'approved_annotations':[]} for i in range(30)]}
        brief=normalized_brief(BRIEF)
        first=task_context(dataset,{'kind':'discovery','categories':['food'],'page':1},brief)
        second=task_context(dataset,{'kind':'discovery','categories':['food'],'page':2},brief)
        self.assertFalse({p['record_id'] for p in first['candidates']} & {p['record_id'] for p in second['candidates']})
        self.assertEqual(second['matching_editorial_occurrences'],30)
    def test_specialist_preferences_keep_daily_baseline(self):
        tasks=task_matrix(normalized_brief({**BRIEF,'interests':['coffee']}))
        self.assertTrue({'attraction','food','coffee'} <= {c for t in tasks for c in t['categories']})


class FieldRetentionRegressionTests(unittest.TestCase):
    def test_selected_check_unknowns_preserve_prior_detail(self):
        first=batch();second=batch()
        first['places'][0].update({'cuisine':'Local','tags':['architecture'],'best_for':['Friends'],'reservation_required':True,'average_visit_minutes':90,'duration_basis':'source'})
        second['places'][0]['average_visit_minutes']=None
        doc=merge_batches([first,second],normalized_brief(BRIEF))
        p=next(p for p in doc['places'] if p['name']=='Synthetic place 0')
        self.assertEqual(p['cuisine'],'Local');self.assertIn('architecture',p['tags'])
        self.assertEqual(p['duration_basis'],'source');self.assertTrue(p['reservation_required'])
    def test_invalid_and_excessive_date_ranges_reject_before_expansion(self):
        for dates in ([1], 42, {'arrival':'2026-01-01','departure':'9999-01-01'}):
            with self.subTest(dates=dates),self.assertRaises(ValueError):normalized_brief({**BRIEF,'date_range':dates})


class ResearchProgressCheckpointTests(unittest.TestCase):
    def test_successful_phases_are_reported_from_actual_work(self):
        with tempfile.TemporaryDirectory() as folder:
            events=[]
            result=run(BRIEF,provider=RecordedProvider(),directory=folder,root=folder,
                dataset=EMPTY_DATASET,progress=lambda step,detail:events.append((step,detail)))
            self.assertEqual(result['pipeline_report']['completed_research_phases'],[2,3,4])
            self.assertTrue(result['pipeline_report']['completed_task_ids'])
            self.assertIn(('phase_completed','checks'),events)
            self.assertEqual(result['delivery_status'],'partial', 'Completed research is not confirmed reservations')

    def test_failed_discovery_never_becomes_completed(self):
        provider=RecordedProvider();research=provider.research
        def fail_later(prompt,task_id):
            if provider.calls: raise TimeoutError('fixture')
            return research(prompt,task_id)
        provider.research=fail_later
        with tempfile.TemporaryDirectory() as folder:
            events=[]
            result=run(BRIEF,provider=provider,directory=folder,root=folder,dataset=EMPTY_DATASET,
                progress=lambda step,detail:events.append((step,detail)))
            self.assertEqual(result['pipeline_report']['completed_research_phases'],[4])
            self.assertNotIn(('phase_completed','discovery'),events)
            self.assertNotIn(('phase_completed','checks'),events)

    def test_bridge_checkpoint_keeps_the_active_task(self):
        import bridge_server
        with tempfile.TemporaryDirectory() as folder, patch.object(bridge_server,'root',return_value=Path(folder)), patch.object(bridge_server,'state',bridge_server.ResearchState()):
            job,_=bridge_server.begin_job(BRIEF)
            bridge_server.progress(job,'searching_web','discovery-food-1')
            bridge_server.progress(job,'phase_completed','discovery')
            status=bridge_server.read_job(job)
            self.assertEqual(status['step'],'searching_web')
            self.assertEqual(status['current_task'],'discovery-food-1')
            self.assertEqual(status['completed_research_phases'],[2])
            bridge_server.progress(job,'phase_completed','discovery')
            self.assertEqual(bridge_server.read_job(job)['completed_research_phases'],[2])
