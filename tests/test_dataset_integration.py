from copy import deepcopy
from contextlib import closing
from pathlib import Path
import sqlite3
import tempfile
import unittest

from tests import test_followup_materialize as fixtures
from trippy.research.dataset_integration import integrate, write_snapshot, verify_snapshot
from trippy.sources.extraction import fingerprint


class DatasetIntegrationTests(unittest.TestCase):
    def fixture(self):
        pack,held,prepared,handoff,cues,audit=fixtures.FollowupTests().fixture()
        layer={'annotations':[],'preserved_manual_reviews':[]}
        identities={'events':[],'summary':{'approved_canonical_places':0}}
        operational={'structured_fields':[],'prose_proposals':[]}
        return pack,held,prepared,handoff,cues,audit,layer,identities,operational

    def test_admission_percentage_is_editorial_not_planner_readiness(self):
        args=self.fixture();before=deepcopy(args);result=integrate(*args)
        self.assertEqual(args,before)
        self.assertEqual(result['readiness']['before_percent'],0)
        self.assertEqual(result['readiness']['after_percent'],100)
        self.assertEqual(result['readiness']['source_slots'],1)
        self.assertFalse(result['readiness']['planner_ready'])
        self.assertFalse(result['ready_to_publish'])
        self.assertEqual(integrate(*args),result)

    def test_prior_manual_holds_are_preserved_without_changing_review(self):
        args=list(self.fixture());old=deepcopy(args[1][0]);old['key']='prior-manual-hold'
        old['followup_review']={'action':'unresolved','reason':'Preserved manual ambiguity.'}
        args[1].append(old)
        result=integrate(*args)
        self.assertEqual(result['held_claims'],[old])
        self.assertEqual(result['readiness']['source_slots'],2)
        self.assertEqual(result['readiness']['after_percent'],50)

    def test_partial_or_duplicate_source_audit_cannot_be_integrated(self):
        for case in ('missing','duplicate'):
            args=list(self.fixture())
            if case=='missing':args[5]['decisions']=[]
            else:args[5]['decisions']*=2
            with self.subTest(case=case),self.assertRaises(ValueError):integrate(*args)

    def test_annotation_with_changed_claim_cannot_inherit_approval(self):
        args=list(self.fixture());claim=args[1][0]['original_claim'];entry={'key':'a',
            'record_id':args[0]['drafts'][0]['id'],'proposal':{'claim_ids':[fingerprint(claim)]}}
        args[6]['annotations']=[{'key':'a','original_entry':entry,'source_entry_sha256':fingerprint(entry),
            'manual_decision':{'evidence_claim_ids':[fingerprint(claim)]},'source_discovery_eligible':True}]
        with self.assertRaisesRegex(ValueError,'fresh comparison'):integrate(*args)

    def test_snapshot_preserves_occurrences_and_detects_semantic_tampering(self):
        bundle=integrate(*self.fixture())
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'dataset.sqlite';write_snapshot(path,bundle)
            original=path.read_bytes();write_snapshot(path,bundle)
            self.assertEqual(path.read_bytes(),original)
            verify_snapshot(path,bundle)
            with closing(sqlite3.connect(path)) as db:
                self.assertEqual(db.execute('SELECT COUNT(*) FROM claims').fetchone()[0],1)
                db.execute("UPDATE claims SET document='{}'")
                db.commit()
            with self.assertRaisesRegex(ValueError,'content differs'):verify_snapshot(path,bundle)

    def test_live_trip_or_canonical_promotions_are_not_accepted(self):
        args=list(self.fixture());args[8]['structured_fields']=[{'current_trip_verified':True}]
        with self.assertRaises(ValueError):integrate(*args)
        args=list(self.fixture());args[7]['events']=[{'status':'canonical_place_approved'}]
        with self.assertRaises(ValueError):integrate(*args)
