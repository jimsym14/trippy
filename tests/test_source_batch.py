import copy
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
from contextlib import closing

from tests import test_creator_extraction as fixtures
from trippy.sources.extraction import aggregate,fingerprint
from trippy.sources.batch import prepare_batch,validate_plan,select_audits,guarded_provider,execute_batch


class SourceBatchTests(unittest.TestCase):
    values={'TRIPPY_LUNA_INPUT_PER_MILLION':'0.30','TRIPPY_LUNA_OUTPUT_PER_MILLION':'1.00',
            'TRIPPY_AI_BUDGET_CURRENCY':'USD','TRIPPY_AI_BUDGET_AMOUNT':'5'}

    def original(self,characters=200,sid='abcdefghijk'):
        chunk,_=fixtures.ExtractionTests().fixture()
        chunk['payload']['source'].update(external_id=sid,url='https://www.youtube.com/watch?v='+sid)
        s=chunk['payload']['segments'][0];s['segment_id']=sid+':000000'
        s['text']='Cafe Example '+('useful travel information '*(characters//26+1))
        s['text']=s['text'][:characters]
        chunk['id']=fingerprint({'prompt':chunk['system_prompt'],'schema':chunk['response_schema'],'payload':chunk['payload']})
        return {'chunks':[chunk]}

    def test_size_tiers_and_total_budget_are_deterministic(self):
        for chars,audits in ((2000,0),(7000,1),(15000,2),(27000,3)):
            original=self.original(chars);plan=prepare_batch(original,self.values,'1.8657948')
            self.assertEqual(plan['videos'][0]['audit_calls'],audits)
            self.assertEqual(plan['summary']['new_calls'],1+audits)
            validate_plan(plan,original)
            changed=copy.deepcopy(plan);changed['videos'][0]['audit_calls']=99
            with self.assertRaises(ValueError):validate_plan(changed,original)

    def test_completed_pilot_and_thin_transcript_do_not_get_paid_runs(self):
        for original,status in ((self.original(2000,'quxiSJMqrHk'),'reuse_completed_pilot'),
                                (self.original(500),'thin_transcript_requires_manual_review')):
            plan=prepare_batch(original,self.values,'1.8657948')
            self.assertEqual(plan['videos'][0]['status'],status)
            self.assertEqual(plan['summary']['new_calls'],0)

    def test_small_audit_keeps_original_cues_and_contract(self):
        chunk,raw=fixtures.ExtractionTests().fixture();base=aggregate([(chunk,raw)])
        selected=select_audits(base,{'chunks':[chunk]},3,self.values)
        self.assertEqual(len(selected['chunks']),1)
        self.assertEqual(selected['chunks'][0]['payload']['segments'],chunk['payload']['segments'])
        self.assertEqual(selected['chunks'][0]['prompt_version'],'coverage-3')

    def test_underfunded_batch_is_rejected_before_any_provider(self):
        original=self.original(2000);plan=prepare_batch(original,self.values,'1.8657948')
        with patch('trippy.sources.batch.guarded_provider') as provider:
            with self.assertRaises(ValueError):execute_batch(plan,original,{**self.values,'TRIPPY_AI_BUDGET_AMOUNT':'1'},'absent.sqlite','absent')
            provider.assert_not_called()

    def test_prior_request_receipt_replays_without_another_call(self):
        chunk,raw=fixtures.ExtractionTests().fixture()
        with tempfile.TemporaryDirectory() as folder:
            ledger=Path(folder)/'budget.sqlite'
            with closing(sqlite3.connect(ledger)) as db,db:
                db.execute('CREATE TABLE extraction_requests(id INTEGER,request_group TEXT,chunk_id TEXT)')
                db.execute('INSERT INTO extraction_requests VALUES(1,?,?)',('test',chunk['id']))
            directory=Path(folder)/'extraction-raw-responses';directory.mkdir()
            (directory/'request-1.json').write_text(json.dumps({'choices':[{'finish_reason':'stop',
                'message':{'content':json.dumps(raw),'refusal':None}}]}))
            with patch('trippy.sources.luna.make_provider') as make:
                make.return_value=lambda c:self.fail('Duplicate paid request')
                provider=guarded_provider(self.values,ledger,'test',1)
                self.assertEqual(provider(chunk),raw)
                (directory/'request-1.json').unlink()
                with self.assertRaises(ValueError):provider(chunk)

    def test_explicit_recovery_is_separate_and_bounded(self):
        chunk,raw=fixtures.ExtractionTests().fixture()
        with tempfile.TemporaryDirectory() as folder:
            ledger=Path(folder)/'budget.sqlite'
            with closing(sqlite3.connect(ledger)) as db,db:
                db.execute('CREATE TABLE extraction_requests(id INTEGER,request_group TEXT,chunk_id TEXT)')
                db.execute('INSERT INTO extraction_requests VALUES(64,?,?)',('test',chunk['id']))
            values={**self.values,'TRIPPY_INTERRUPTED_REQUESTS':'64'}
            with patch('trippy.sources.batch.request_with_deadline',return_value=raw) as call:
                self.assertEqual(guarded_provider(values,ledger,'test',1)(chunk),raw)
                self.assertEqual(call.call_args.args[0]['TRIPPY_LUNA_REQUEST_GROUP'],'test-recovery-64')
                self.assertEqual(call.call_args.args[0]['TRIPPY_LUNA_MAX_REQUESTS'],'1')
                with closing(sqlite3.connect(ledger)) as db,db:
                    db.execute('INSERT INTO extraction_requests VALUES(66,?,?)',('test-recovery-64',chunk['id']))
                with self.assertRaises(ValueError):guarded_provider(values,ledger,'test',1)(chunk)
                self.assertEqual(call.call_count,1)


if __name__=='__main__':unittest.main()
