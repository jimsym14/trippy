from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from tests import test_semantic_materialize as fixtures
from trippy.sources.extraction import fingerprint
from trippy.sources.luna import reserve_cost, TransientProviderError
from trippy.sources.semantic_materialize import materialize
from trippy.sources.semantic_review import reservation
from trippy.research.reviews import source_chunk, page_chunk
from trippy.research.queue import Runner, job
from trippy.research.completion import export


class FakeClock:
    def __init__(self): self.value=1000
    def now(self): return self.value
    def sleep(self,seconds): self.value+=seconds


class ResearchQueueTests(unittest.TestCase):
    def fixture(self,folder):
        records,cues,prepared,effective,_=fixtures.SemanticMaterializeTests().fixture()
        initial=materialize(records,cues,prepared,effective,[])
        pack=initial['normalized']; pack['previous_to_normalized_ids']={r['id']:r['id'] for r in pack['drafts']}
        folder=Path(folder)
        for name,data in [('pack',pack),('held',initial['held_claims']),('audit',{'reviews':[]})]:
            (folder/(name+'.json')).write_text(json.dumps(data))
        config=json.loads(Path('configs/source_research/barcelona-completion-v1.json').read_text())
        config.pop('annotation_proposals',None)
        config.update(output_root=str(folder/'run'),ledger=str(folder/'ledger.sqlite'),
            pack=str(folder/'pack.json'),held=str(folder/'held.json'),manual_tag_audit=str(folder/'audit.json'),
            request_prefix='synthetic-completion',extract_operator_prose=False,max_total_wait_seconds=1000)
        reserve_cost(config['ledger'],Decimal('1'),Decimal('15'),'USD')
        values={'TRIPPY_AI_BUDGET_CURRENCY':'USD','TRIPPY_AI_BUDGET_AMOUNT':'15',
            'TRIPPY_LUNA_INPUT_PER_MILLION':'0.30','TRIPPY_LUNA_OUTPUT_PER_MILLION':'1',
            'TRIPPY_ALLOW_PAID_RESEARCH':'true'}
        entry=prepared['chunks'][0]['payload']['entries'][0]
        request=source_chunk([entry],cues); source=job('source',{'request':request})
        identity=job('identity_inventory',{'groups':[],'status':'synthetic'})
        plan={'config':config,'jobs':[source,identity],'deferred_operator_urls':[]}
        fields={k:v for k,v in effective['decisions'][0].items() if k not in {'key','original_entry_sha256','approval'}}
        fields.update(assertion_scope='general',lifecycle='creator_opinion',subject_note='Synthetic general advice.')
        response={'decisions':{entry['key']:fields}}
        return plan,values,response

    def requester(self,response,clock=None,fail=None):
        calls=[]
        def request(values,ledger,chunk):
            amount=reservation(chunk,values,output=int(values['TRIPPY_LUNA_MAX_OUTPUT_TOKENS']))
            reserve_cost(ledger,amount,Decimal('15'),'USD',group=values['TRIPPY_LUNA_REQUEST_GROUP'],chunk_id=chunk['id'],max_requests=100)
            calls.append(clock.now() if clock else chunk['id'])
            if fail and len(calls)<=fail: raise TransientProviderError('rate_limit',60)
            return deepcopy(response)
        return request,calls

    def test_resume_is_free_and_export_conserves_claims_without_overwriting_active_pack(self):
        with TemporaryDirectory() as folder:
            plan,values,response=self.fixture(folder); before=Path(plan['config']['pack']).read_text()
            request,calls=self.requester(response)
            runner=Runner(plan,values,requester=request); runner.run()
            report=export(runner)
            self.assertEqual(report['editorial']['claims_conserved'],1)
            self.assertEqual(report['editorial']['staged_active_claims'],1)
            self.assertFalse(report['ready_to_publish'])
            self.assertEqual(Path(plan['config']['pack']).read_text(),before)
            resumed=Runner(plan,values,requester=lambda *a: self.fail('Paid request on resume'))
            resumed.run(); self.assertEqual(len(calls),1)

    def test_rate_limit_cools_down_provider_while_local_and_http_work_continues(self):
        with TemporaryDirectory() as folder:
            plan,values,response=self.fixture(folder); clock=FakeClock()
            source_request,calls=self.requester(response,clock=clock,fail=1)
            def request(values,ledger,chunk):
                if values['TRIPPY_LUNA_REQUEST_GROUP'].endswith('operator_extract'):
                    calls.append(clock.now()); return {'facts':[]}
                return source_request(values,ledger,chunk)
            web=job('operator_fetch',{'url':'https://operator.test/','candidates':[]})
            plan['jobs'].append(web); times=[]
            page=page_chunk({'url':'https://operator.test/','sections':[{'id':'s1','text':'Cafe A'}]})
            plan['jobs'].append(job('operator_extract',{'request':page,'source_checked_at':'2026-11-01T10:00:00+00:00','source_body_sha256':'synthetic'}))
            def fetch(url,request_hook):
                request_hook('operator.test'); times.append(clock.now())
                return {'sections':[],'structured_observations':[],'url':url,'checked_at':'2026-11-01T10:00:00+00:00','body_sha256':'synthetic'}
            runner=Runner(plan,values,requester=request,fetcher=fetch,sleep=clock.sleep,now=clock.now)
            runner.run()
            self.assertEqual(calls,[1000,1060,1060]); self.assertEqual(times,[1000])
            self.assertEqual(runner.checkpoint()['jobs'],{'succeeded':4})
            self.assertEqual(runner.store.http_count(),1)

    def test_invalid_content_is_retained_without_paid_retry_and_other_jobs_finish(self):
        with TemporaryDirectory() as folder:
            plan,values,_=self.fixture(folder); request,calls=self.requester({'decisions':{}})
            runner=Runner(plan,values,requester=request); runner.run()
            self.assertEqual(runner.checkpoint()['jobs'],{'review_required':1,'succeeded':1})
            runner.run(); self.assertEqual(len(calls),1)
            self.assertEqual(export(runner)['editorial']['held_claims'],1)

    def test_budget_defer_does_not_consume_attempts_or_block_local_identity(self):
        with TemporaryDirectory() as folder:
            plan,values,_=self.fixture(folder); plan['config']['task_caps']['source']='0.000001'
            runner=Runner(plan,values,requester=lambda *a:self.fail('Budget exceeded'))
            runner.run(); source=next(r for r in runner.store.rows() if r['kind']=='source')
            self.assertEqual(source['state'],'budget_deferred'); self.assertEqual(source['attempts'],0)
            self.assertEqual(runner.checkpoint()['jobs']['succeeded'],1)

    def test_interrupted_provider_receipt_is_adopted_even_at_attempt_limit(self):
        with TemporaryDirectory() as folder:
            plan,values,response=self.fixture(folder); plan['config']['max_attempts']=1
            def interrupted(values,ledger,chunk):
                rid=reserve_cost(ledger,reservation(chunk,values,output=3000),Decimal('15'),'USD',
                    group=values['TRIPPY_LUNA_REQUEST_GROUP'],chunk_id=chunk['id'],max_requests=100)
                raw=Path(ledger).parent/'extraction-raw-responses'; raw.mkdir()
                (raw/f'request-{rid}.json').write_text(json.dumps({'choices':[{'finish_reason':'stop','message':{'content':json.dumps(response)}}]}))
                raise KeyboardInterrupt()
            runner=Runner(plan,values,requester=interrupted)
            with self.assertRaises(KeyboardInterrupt): runner.run()
            resumed=Runner(plan,values,requester=lambda *a:self.fail('Receipt should have been adopted'))
            resumed.run(); self.assertEqual(resumed.checkpoint()['jobs'],{'succeeded':2})

    def test_wait_limit_is_persisted_and_does_not_busy_retry(self):
        with TemporaryDirectory() as folder:
            plan,values,_=self.fixture(folder); plan['config']['max_total_wait_seconds']=30
            clock=FakeClock()
            def request(*args): raise TransientProviderError('rate_limit',3600)
            runner=Runner(plan,values,requester=request,sleep=clock.sleep,now=clock.now)
            runner.run(); self.assertEqual(clock.now(),1000)
            self.assertEqual(runner.checkpoint()['jobs'],{'blocked':1,'succeeded':1})

    def test_input_and_saved_result_tampering_are_rejected(self):
        with TemporaryDirectory() as folder:
            plan,values,response=self.fixture(folder); request,_=self.requester(response)
            runner=Runner(plan,values,requester=request); runner.run()
            changed=deepcopy(plan); changed['config']['max_attempts']=2
            with self.assertRaises(ValueError): Runner(changed,values)
            row=next(r for r in runner.store.rows() if r['kind']=='source')
            Path(row['result_path']).write_text('{}')
            with self.assertRaises(ValueError): runner.run()

    def test_dynamic_prose_job_is_checkpointed_and_not_repeated_on_resume(self):
        with TemporaryDirectory() as folder:
            plan,values,response=self.fixture(folder); plan['config']['extract_operator_prose']=True
            plan['jobs'].append(job('operator_fetch',{'url':'https://operator.test/','candidates':[]}))
            calls=[]
            def request(values,ledger,chunk):
                calls.append(chunk['id'])
                return {'facts':[]} if 'sections' in chunk['payload'] else response
            def fetch(url,request_hook):
                return {'sections':[{'id':'s1','text':'Cafe A coffee'}],'structured_observations':[],
                    'url':url,'checked_at':'2026-11-01T10:00:00+00:00','body_sha256':'synthetic'}
            runner=Runner(plan,values,requester=request,fetcher=fetch); runner.run()
            self.assertEqual(runner.checkpoint()['jobs'],{'succeeded':4})
            resumed=Runner(plan,values,requester=lambda *a:self.fail('Repeated inference'),fetcher=lambda *a,**kw:self.fail('Repeated fetch'))
            resumed.run(); self.assertEqual(len(calls),2)

    def test_new_run_reuses_fresh_http_receipt_without_advancing_checked_at(self):
        with TemporaryDirectory() as folder:
            plan,values,_=self.fixture(folder); clock=FakeClock(); calls=[]
            plan['jobs']=[job('operator_fetch',{'url':'https://operator.test/','candidates':[]})]
            def fetch(url,request_hook):
                request_hook('operator.test'); calls.append(url)
                return {'sections':[],'structured_observations':[],'url':url,
                    'checked_at':'1970-01-01T00:16:40+00:00','body_sha256':'synthetic'}
            first=Runner(plan,values,fetcher=fetch,sleep=clock.sleep,now=clock.now); first.run()
            refreshed=deepcopy(plan); refreshed['config']['output_root']=str(Path(folder)/'refresh')
            clock.sleep(120)
            second=Runner(refreshed,values,fetcher=lambda *a,**kw:self.fail('Fresh cache should be reused'),sleep=clock.sleep,now=clock.now)
            second.run(network=False,ai=False)
            receipt=second.result(second.store.rows()[0])['result']
            self.assertEqual(len(calls),1); self.assertEqual(second.store.http_count(),0)
            self.assertEqual(receipt['checked_at'],'1970-01-01T00:16:40+00:00')
            self.assertTrue(receipt['cache_reused'])
