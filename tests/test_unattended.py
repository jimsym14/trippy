from copy import deepcopy
from decimal import Decimal
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from trippy.sources.extraction import fingerprint
from trippy.sources.luna import TransientProviderError, retry_hint, reserve_cost, make_provider
from trippy.sources.unattended import prepare_chunks, validate_annotations, execute, retry_delay, recover_provider_response
from trippy.sources.batch import request_with_deadline
import time
import trippy.sources.unattended as queue


REGISTRY = json.loads((Path(__file__).resolve().parents[1]/'configs/activity-registry-v1.json').read_text())


def record(name='Cafe', record_id='a', claims=True):
    return {'id':record_id,'upstream_occurrence_id':'upstream-'+record_id,'name':name,
        'kind':'venue','branch':None,'identity_uncertain':False,'categories':['coffee'],
        'source':{'external_id':'video'},'claims':[{'dimension':'subcategory',
            'value':'The creator visited this specialty coffee shop.','basis':'creator_opinion',
            'observed_at':None,'citations':[{'segment_id':'video:000001','quote':'specialty coffee',
                'start_seconds':1.,'end_seconds':2.}]}] if claims else []}


def response(chunk):
    return {'records':{e['record_id']:{'facets':[],'details':[],
        'activity_fit_proposals':[],'unrepresented_claim_ids':[c['id'] for c in e['claims']],
        'review_note':'No automatic approval.'} for e in chunk['payload']['entries']}}


def stalled_worker(values,ledger,chunk,connection):
    time.sleep(1)


def transient_worker(values,ledger,chunk,connection):
    connection.send(('error','TransientProviderError','redacted',{'kind':'rate_limit','retry_after_seconds':123}))
    connection.close()


class UnattendedTests(unittest.TestCase):
    def test_evidence_slots_closed_values_and_accounting(self):
        chunk = prepare_chunks([record(),record(record_id='b')],REGISTRY)[0]
        good = response(chunk)
        self.assertEqual(validate_annotations(chunk,good,REGISTRY),good)
        for kind in ('missing_slot','missing_claim','unknown_evidence','closed_value','trip_tag'):
            bad = deepcopy(good); result = bad['records']['a']
            if kind=='missing_slot': bad['records'].pop('b')
            elif kind=='missing_claim': result['unrepresented_claim_ids']=[]
            else:
                own = chunk['payload']['entries'][0]['claims'][0]['id']
                result['facets']=[{'key':'service','value':'coffee','claim_ids':[own]}]
                result['unrepresented_claim_ids']=[]
                if kind=='unknown_evidence': result['facets'][0]['claim_ids']=['invented']
                if kind=='closed_value': result['facets'][0]['value']='unlimited_free_coffee'
                if kind=='trip_tag': result['facets'][0]['key']='coffee_every_day'
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                validate_annotations(chunk,bad,REGISTRY)

    def test_multi_capability_and_empty_sources(self):
        chunk = prepare_chunks([record(),record(record_id='empty',claims=False)],REGISTRY)[0]
        self.assertEqual(len(chunk['payload']['entries']),1)
        result = response(chunk); own=chunk['payload']['entries'][0]['claims'][0]['id']
        result['records']['a']['facets']=[{'key':'service','value':v,'claim_ids':[own]} for v in ['coffee','pastries']]
        result['records']['a']['unrepresented_claim_ids']=[]
        validate_annotations(chunk,result,REGISTRY)  # semantic fit still awaits manual review

    def fixture(self,directory):
        root=Path(directory); ledger=root/'ledger.sqlite'
        reserve_cost(ledger,Decimal('.001'),Decimal('15'),'USD',group='previous',chunk_id='previous')
        chunks=prepare_chunks([record()],REGISTRY)
        document={'version':1,'engine_sha256':fingerprint(Path(queue.__file__).read_text()),
            'registry':REGISTRY,'stages':[{'name':'venue','request_group':'queue-test','task_cap':'1',
                'chunks':chunks}], 'config':{'output_root':str(root/'output'),'ledger':str(ledger),
                'shared_cap':'15','queue_cap':'1','max_attempts_per_chunk':3,
                'max_total_wait_seconds':43200,'output_tokens':6000,'max_requests_per_stage':100,
                'provider_timeout_seconds':120,'worker_timeout_seconds':180}}
        values={'TRIPPY_AI_BUDGET_AMOUNT':'15','TRIPPY_AI_BUDGET_CURRENCY':'USD',
            'TRIPPY_LUNA_INPUT_PER_MILLION':'.3','TRIPPY_LUNA_OUTPUT_PER_MILLION':'1'}
        return document, values

    def charge(self,values,ledger,chunk):
        reserve_cost(ledger,Decimal('.02'),Decimal('15'),'USD',
            group=values['TRIPPY_LUNA_REQUEST_GROUP'],chunk_id=chunk['id'])

    def test_rate_limit_wait_resume_and_no_duplicate_payment(self):
        with TemporaryDirectory() as directory:
            document,values=self.fixture(directory); calls=[]; sleeps=[]
            def requester(v,ledger,chunk):
                self.charge(v,ledger,chunk); calls.append(chunk['id'])
                if len(calls)==1: raise TransientProviderError('rate_limit',65)
                return response(chunk)
            report=execute(document,values,requester=requester,sleep=sleeps.append)
            self.assertEqual(report['state'],'proposals_complete_manual_review_required')
            self.assertEqual(len(calls),2); self.assertAlmostEqual(sum(sleeps),65,delta=.02)
            def forbidden(*args): self.fail('Saved response must not be paid again')
            resumed=execute(document,values,requester=forbidden,sleep=sleeps.append)
            self.assertEqual(resumed['completed_calls'],1)
            self.assertFalse(resumed['ready_to_publish'])

    def test_persistent_retry_ceiling_and_continue_independent_chunk(self):
        with TemporaryDirectory() as directory:
            document,values=self.fixture(directory)
            document['stages'][0]['chunks']=prepare_chunks([record(),record(record_id='b')],REGISTRY,batch_size=1)
            first=document['stages'][0]['chunks'][0]['id']; calls=[]
            def requester(v,ledger,chunk):
                self.charge(v,ledger,chunk); calls.append(chunk['id'])
                if chunk['id']==first: raise TransientProviderError('timeout')
                return response(chunk)
            report=execute(document,values,requester=requester,sleep=lambda _:None)
            self.assertEqual(calls.count(first),3); self.assertEqual(report['completed_calls'],1)
            execute(document,values,requester=lambda *a:self.fail('Exhausted or saved work cannot be redispatched'))

    def test_invalid_response_is_saved_without_paid_retry(self):
        with TemporaryDirectory() as directory:
            document,values=self.fixture(directory); calls=[]
            def requester(v,ledger,chunk):
                self.charge(v,ledger,chunk); calls.append(chunk['id']); return {'records':{}}
            report=execute(document,values,requester=requester)
            self.assertEqual(report['completed_calls'],0)
            self.assertTrue(list((Path(directory)/'output/venue').glob('*.candidate.json')))
            execute(document,values,requester=lambda *a:self.fail('Invalid candidate must not trigger a retry'))
            self.assertEqual(len(calls),1)

    def test_budget_stops_before_dispatch_and_configuration_halts(self):
        with TemporaryDirectory() as directory:
            document,values=self.fixture(directory); document['config']['queue_cap']='.0001'
            document['stages'][0]['task_cap']='.0001'
            report=execute(document,values,requester=lambda *a:self.fail('No room for request'))
            self.assertEqual(report['state'],'shared_or_queue_budget_reached')

    def test_retry_after_numeric_and_http_date(self):
        class Response: headers={'retry-after-ms':'1250'}
        class Error: response=Response()
        self.assertEqual(retry_hint(Error()),1.25)
        self.assertEqual(retry_delay(TransientProviderError('rate_limit',120),1),120)

    def test_worker_hints_and_hard_wall_deadline(self):
        with self.assertRaises(TransientProviderError) as caught:
            request_with_deadline({},'unused',{},timeout=3,worker=transient_worker)
        self.assertEqual(caught.exception.retry_after_seconds,123)
        with self.assertRaises(TransientProviderError) as caught:
            request_with_deadline({},'unused',{},timeout=.05,worker=stalled_worker,retryable_deadline=True)
        self.assertEqual(caught.exception.kind,'worker_deadline')

    def test_raw_response_recovered_after_interruption_without_api(self):
        with TemporaryDirectory() as directory:
            document,values=self.fixture(directory); chunk=document['stages'][0]['chunks'][0]
            ledger=document['config']['ledger']; self.charge({'TRIPPY_LUNA_REQUEST_GROUP':'queue-test'},ledger,chunk)
            import sqlite3
            with sqlite3.connect(ledger) as db:
                request_id=db.execute('SELECT MAX(id) FROM extraction_requests').fetchone()[0]
            folder=Path(ledger).parent/'extraction-raw-responses'; folder.mkdir()
            (folder/f'request-{request_id}.json').write_text(json.dumps({'choices':[{
                'finish_reason':'stop','message':{'content':json.dumps(response(chunk))}}]}))
            self.assertEqual(recover_provider_response(ledger,'queue-test',chunk['id']),response(chunk))
            report=execute(document,values,requester=lambda *a:self.fail('Must adopt saved completion'))
            self.assertEqual(report['completed_calls'],1)

    def test_provider_preserves_redacted_transient_hint(self):
        class FakeResponse: headers={'retry-after':'90'}
        class RateLimited(Exception): status_code=429; response=FakeResponse()
        class Completions:
            def create(self,**kwargs): raise RateLimited('secret must never appear')
        class Client:
            def __init__(self,**kwargs): self.chat=type('Chat',(),{'completions':Completions()})()
        with TemporaryDirectory() as directory:
            document,values=self.fixture(directory)
            values.update(TRIPPY_ALLOW_PAID_RESEARCH='true',AZURE_OPENAI_API_KEY='test-key-valid',
                AZURE_DEPLOYMENT_LUNA='test-luna-deployment',AZURE_OPENAI_ENDPOINT='https://test.openai.azure.com')
            provider=make_provider(values,document['config']['ledger'],client_factory=Client)
            with self.assertRaises(TransientProviderError) as raised:
                provider(document['stages'][0]['chunks'][0])
            self.assertEqual(raised.exception.retry_after_seconds,90)
            self.assertNotIn('secret',str(raised.exception))


if __name__=='__main__': unittest.main()
