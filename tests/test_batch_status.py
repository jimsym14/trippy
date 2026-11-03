from contextlib import closing
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from trippy.sources.batch_status import snapshot


class BatchStatusTests(unittest.TestCase):
    def test_monitor_filters_batch_and_handles_in_progress_receipt_without_spending(self):
        plan={'plan_sha256':'abc','summary':{'new_calls':3},'videos':[
            {'source_id':'abcdefghijk','title':'Test video','status':'scheduled'}]}
        with tempfile.TemporaryDirectory() as folder:
            ledger=Path(folder)/'budget.sqlite';root=Path(folder)/'results'
            with closing(sqlite3.connect(ledger)) as db,db:
                db.execute('CREATE TABLE extraction_budget(id INTEGER,reserved TEXT)')
                db.execute('INSERT INTO extraction_budget VALUES(1,"2.0780328")')
                db.execute('CREATE TABLE extraction_requests(id INTEGER,request_group TEXT,created_at TEXT,amount TEXT)')
                for row in ((1,'earlier-pilot','2026-10-30T20:00:00+00:00','0.02'),
                            (2,'barcelona-size-v1-abc-abcdefghijk-primary','2026-10-30T20:01:00+00:00','0.03'),
                            (3,'barcelona-size-v1-abc-abcdefghijk-audit','2026-10-30T20:02:00+00:00','0.04')):
                    db.execute('INSERT INTO extraction_requests VALUES(?,?,?,?)',row)
            receipts=Path(folder)/'extraction-raw-responses';receipts.mkdir()
            (receipts/'request-2.json').write_text(json.dumps({'choices':[{'finish_reason':'stop'}],
                'usage':{'prompt_tokens':100,'completion_tokens':1000}}))
            (receipts/'request-3.json').write_text('{')
            first=snapshot(plan,ledger,root,rates={'input':'0.3','output':'1'})
            self.assertEqual(first['started'],2);self.assertEqual(first['received'],1)
            self.assertEqual(len(first['pending']),1);self.assertEqual(first['reserved'],'2.0780328')
            self.assertEqual(first['tasks'][0]['primary']['reserved'],'0.03')
            self.assertEqual(first['tasks'][0]['audit']['reserved'],'0.04')
            self.assertEqual(first['batch_reserved'],'0.07')
            self.assertEqual(first['batch_estimated'],'0.00103')
            self.assertEqual(first['usage_receipts'],1)
            (root/'abcdefghijk').mkdir(parents=True);(root/'abcdefghijk'/'final.json').write_text('{}')
            (receipts/'request-3.json').write_text(json.dumps({'choices':[{'finish_reason':'length'}]}))
            second=snapshot(plan,ledger,root)
            self.assertEqual(second['finished'],1);self.assertEqual(second['incomplete'],1)
            self.assertFalse(second['pending'])
            with closing(sqlite3.connect(ledger)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM extraction_requests').fetchone()[0],3)
            summary=Path(folder)/'summary.json';summary.write_text(json.dumps({'failed_videos':[{'source_id':'other'}]}))
            done=snapshot(plan,ledger,root,summary_path=summary)
            self.assertTrue(done['batch_complete']);self.assertEqual(done['failed_videos'],1)


if __name__=='__main__':unittest.main()
