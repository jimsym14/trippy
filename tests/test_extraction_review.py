import copy
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from contextlib import closing

from tests import test_creator_extraction as fixtures
from trippy.sources.review import partition_mentions, repair_citations, review_responses


class EvidenceReviewTests(unittest.TestCase):
    def fixture(self):
        return fixtures.ExtractionTests().fixture()

    def test_unique_exact_quote_repairs_id_and_derives_time(self):
        chunk,raw=self.fixture()
        mention=raw['mentions'][0]
        mention['citations'][0].update(segment_id='wrong',start_seconds=7,end_seconds=8)
        repaired,changes=repair_citations(mention,chunk)
        self.assertEqual(repaired['citations'][0]['segment_id'],'abcdefghijk:000000')
        self.assertEqual(repaired['citations'][0]['start_seconds'],0.)
        self.assertEqual(repaired['citations'][0]['end_seconds'],10.)
        self.assertEqual(repaired['citations'][0]['quote'],mention['citations'][0]['quote'])
        self.assertEqual(len(changes),1)
        self.assertEqual(mention['citations'][0]['segment_id'],'wrong')

    def test_ambiguous_and_missing_quotes_are_not_repaired(self):
        for missing in (False,True):
            chunk,raw=self.fixture()
            segment=copy.deepcopy(chunk['payload']['segments'][0])
            segment['segment_id']='duplicate'
            chunk['payload']['segments'].append(segment)
            mention=raw['mentions'][0]
            mention['citations'][0]['segment_id']='wrong'
            if missing:mention['citations'][0]['quote']='Invented words'
            repaired,changes=repair_citations(mention,chunk)
            self.assertFalse(changes)
            self.assertEqual(repaired,mention)
            accepted,rejected,_=partition_mentions(chunk,{'mentions':[mention]})
            self.assertFalse(accepted['mentions'])
            self.assertEqual(rejected[0]['kind'],'mention')

    def test_invalid_mention_and_claim_do_not_discard_valid_evidence(self):
        chunk,raw=self.fixture()
        bad=copy.deepcopy(raw['mentions'][0]);bad['name']='Unsupported venue'
        raw['mentions'].append(bad)
        claim=copy.deepcopy(raw['mentions'][0]['claims'][0])
        claim['citations'][0]['quote']='Invented claim quote'
        raw['mentions'][0]['claims'].append(claim)
        accepted,rejected,_=partition_mentions(chunk,raw)
        self.assertEqual(len(accepted['mentions']),1)
        self.assertEqual(len(accepted['mentions'][0]['claims']),1)
        self.assertEqual({r['kind'] for r in rejected},{'mention','claim'})

    def test_unsupported_rating_quarantined_without_discarding_venue(self):
        chunk,raw=self.fixture()
        raw['mentions'][0]['rating']={'value':4.5,'scale':5,'platform':'Google',
            'citations':copy.deepcopy(raw['mentions'][0]['citations'])}
        accepted,rejected,_=partition_mentions(chunk,raw)
        self.assertIsNone(accepted['mentions'][0]['rating'])
        self.assertEqual(rejected[0]['kind'],'rating')

    def test_retry_responses_do_not_invent_independent_publishers(self):
        chunk,raw=self.fixture()
        with tempfile.TemporaryDirectory() as directory:
            ledger=Path(directory)/'budget.sqlite'
            with closing(sqlite3.connect(ledger)) as db:
                db.execute('CREATE TABLE extraction_requests(id INTEGER,chunk_id TEXT,request_group TEXT)')
                db.executemany('INSERT INTO extraction_requests VALUES(?,?,?)',
                    [(1,chunk['id'],'pilot'),(2,chunk['id'],'pilot'),(3,chunk['id'],'other')])
                db.commit()
            folder=Path(directory)/'extraction-raw-responses';folder.mkdir()
            response={'choices':[{'finish_reason':'stop','message':{'content':json.dumps(raw),'refusal':None}}]}
            for request_id in (1,2):
                (folder/f'request-{request_id}.json').write_text(json.dumps(response))
            report=review_responses({'chunks':[chunk]},ledger,group='pilot')
        self.assertEqual(len(report['response_receipts']),2)
        self.assertEqual(report['summary']['draft_mentions'],1)
        self.assertEqual(report['review_queue'][0]['independent_publisher_count'],1)
        self.assertEqual(report['catalog_writes'],0)
        self.assertEqual(report['additional_model_calls'],0)
        self.assertEqual(report['fact_check_status'],'not_independently_fact_checked')


if __name__=='__main__':unittest.main()
