import json
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

from tests.test_source_batch import SourceBatchTests
from trippy.sources.batch import prepare_batch
from trippy.sources.batch_recovery import prepare, execute


class RecoveryTests(unittest.TestCase):
    def fixture(self, root):
        values=SourceBatchTests.values
        original=SourceBatchTests().original(2000)
        plan=prepare_batch(original,values,'0')
        v=plan['videos'][0];c=v['chunks'][0]
        folder=root/v['source_id'];folder.mkdir()
        base={'batch_plan_sha256':plan['plan_sha256'],'drafts':[],
            'primary_failures':[{'chunk_id':c['id'],'error_type':'ValueError','reason':'timeout'}],
            'source_evidence_inventory':c['payload']['segments']}
        path=folder/'final.json';path.write_text(json.dumps(base))
        ledger=root/'budget.sqlite'
        with closing(sqlite3.connect(ledger)) as db,db:
            db.execute('CREATE TABLE extraction_budget(id INTEGER,reserved TEXT)')
            db.execute('INSERT INTO extraction_budget VALUES(1,"0")')
            db.execute('CREATE TABLE extraction_requests(request_group TEXT,chunk_id TEXT)')
        return plan,values,ledger,path

    def test_separate_version_preserves_original_and_replays_final(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);plan,values,ledger,path=self.fixture(root)
            before=path.read_bytes();manifest=prepare(plan,root,values)
            with patch('trippy.sources.batch_recovery.guarded_provider',return_value=lambda c:{'mentions':[]}) as provider:
                result=execute(manifest,values,ledger,root/'recovery')
                self.assertTrue(result['videos'][0]['failed_passages_recovered'])
                self.assertEqual(path.read_bytes(),before)
                execute(manifest,values,ledger,root/'recovery')
                self.assertEqual(provider.call_count,1)

    def test_shared_cap_rejects_before_dispatch(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);plan,values,ledger,path=self.fixture(root)
            manifest=prepare(plan,root,values)
            with patch('trippy.sources.batch_recovery.guarded_provider') as provider:
                with self.assertRaises(ValueError):execute(manifest,{**values,'TRIPPY_AI_BUDGET_AMOUNT':'0'},ledger,root/'recovery')
                provider.assert_not_called()


if __name__=='__main__':unittest.main()
