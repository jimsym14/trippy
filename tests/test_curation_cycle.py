from contextlib import closing
from copy import deepcopy
from pathlib import Path
import sqlite3
import tempfile
import unittest

from tests import test_creator_extraction as fixtures
from trippy.sources.extraction import aggregate, fingerprint
from trippy.sources.curation_cycle import apply_decisions, has_term, run_cycle, validate_observations


class CurationCycleTests(unittest.TestCase):
    def fixture(self):
        chunk,raw=fixtures.ExtractionTests().fixture()
        records=aggregate([(chunk,raw)])['drafts']
        cues={c['segment_id']:c for c in chunk['payload']['segments']}
        decision={'occurrence_id':records[0]['id'],'action':'claim_dimension',
            'claim_sha256':fingerprint(records[0]['claims'][0]),'dimension':'recommendation',
            'review_method':'agent_source_comparison','reason':'Synthetic source-comparison test.'}
        return records,cues,decision

    def test_correction_preserves_input_quotes_and_versions(self):
        records,cues,decision=self.fixture();before=deepcopy(records)
        updated,events,mapping=apply_decisions(records,[decision],cues)
        self.assertEqual(records,before)
        self.assertEqual(updated[0]['claims'][0]['citations'],before[0]['claims'][0]['citations'])
        self.assertEqual(events[0]['original'],before[0])
        self.assertEqual(mapping[before[0]['id']],updated[0]['id'])
        with self.assertRaises(ValueError):apply_decisions(records,[{**decision,'claim_sha256':'stale'}],cues)

    def test_split_cannot_rewrite_evidence(self):
        records,cues,decision=self.fixture();claim=records[0]['claims'][0]
        second={**deepcopy(claim),'dimension':'other'}
        second['citations'][0]['quote']='invented'
        decision.update(action='claim_split',claims=[claim,second])
        with self.assertRaises(ValueError):apply_decisions(records,[decision],cues)

    def test_keyword_substrings_do_not_claim_niche_coverage(self):
        self.assertFalse(has_term('Modern technology',['techno']))
        self.assertFalse(has_term('Fork-breakfast food',['fast food']))
        self.assertTrue(has_term('A techno programme',['techno']))

    def test_cycle_replay_and_release_gates(self):
        records,cues,decision=self.fixture()
        profile={'city_id':'synthetic','coverage_cells':[]}
        with tempfile.TemporaryDirectory() as folder:
            a,path=run_cycle('synthetic',records,cues,[],[decision],profile,[],folder)
            b,_=run_cycle('synthetic',records,cues,[],[decision],profile,[],folder)
            self.assertEqual(a,b);self.assertFalse(a['ready_to_publish'])
            with closing(sqlite3.connect(Path(folder)/'synthetic'/'curation.sqlite')) as db:
                self.assertEqual(db.execute('SELECT count(*) FROM curation_runs').fetchone()[0],1)
                self.assertEqual(db.execute('SELECT count(*) FROM curation_events').fetchone()[0],1)
            self.assertEqual(a['model_api_calls'],0)

    def test_external_observation_cannot_claim_blanket_safety(self):
        observation={'id':'one','source_url':'https://example.com','retrieved_at':'2026-10-31',
            'review_method':'agent_primary_page_comparison','current_trip_verified':False,
            'allergy_safe':True,'rating':None}
        with self.assertRaises(ValueError):validate_observations([observation])

    def test_additional_citation_cannot_invent_or_cross_source_evidence(self):
        records,cues,decision=self.fixture()
        claim=records[0]['claims'][0]
        bad={**deepcopy(claim['citations'][0]),'quote':'invented additional evidence'}
        decision.update(action='claim_citations_add',additional_citations=[bad])
        with self.assertRaises(ValueError):apply_decisions(records,[decision],cues)
        bad['segment_id']='another-video:000000'
        with self.assertRaises(ValueError):apply_decisions(records,[decision],cues)


if __name__=='__main__':unittest.main()
