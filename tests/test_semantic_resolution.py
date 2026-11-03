import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from copy import deepcopy

from tests import test_semantic_review as fixtures
from trippy.sources.extraction import fingerprint
from trippy.sources.semantic_review import recover_review
from trippy.sources.semantic_resolution import worklist, resolve


class SemanticResolutionTests(unittest.TestCase):
    def fixture(self, root):
        chunk, response = fixtures.SemanticReviewTests().fixture()
        prepared = {'chunks':[chunk], 'claim_occurrences':len(response['decisions'])}
        raw = {'decisions':[]}; cache = recover_review(chunk, raw); cache['raw_response'] = raw
        Path(root, chunk['id']+'.json').write_text(json.dumps(cache))
        pending, _ = worklist(prepared, root)
        manual = {'review_method':'agent_source_comparison', 'worklist_sha256':fingerprint(pending),
            'decisions':[{**d, 'original_entry_sha256':fingerprint(e)}
                for d,e in zip(response['decisions'],chunk['payload']['entries'])]}
        return prepared, manual

    def test_resolution_is_source_bound_and_does_not_publish_or_apply_repairs(self):
        with TemporaryDirectory() as root:
            prepared, manual = self.fixture(root)
            result = resolve(prepared, root, manual)
            self.assertTrue(result['summary']['source_disposition_pass_complete'])
            self.assertFalse(result['summary']['planner_ready'])
            self.assertEqual(result['paid_model_calls'],0)
            self.assertIn('agent_source_comparison', result['decisions'][0]['approval'])
            self.assertEqual(resolve(prepared, root, manual), result)

    def test_stale_duplicate_missing_and_cross_source_decisions_rejected(self):
        with TemporaryDirectory() as root:
            prepared, manual = self.fixture(root)
            for mutation in ('stale','duplicate','missing','evidence','inputs','method'):
                bad = deepcopy(manual)
                if mutation == 'stale': bad['decisions'][0]['original_entry_sha256']='stale'
                if mutation == 'duplicate': bad['decisions'] *= 2
                if mutation == 'missing': bad['decisions']=[]
                if mutation == 'evidence': bad['decisions'][0]['evidence_segment_ids']=['other-video:000000']
                if mutation == 'inputs': bad['worklist_sha256']='different'
                if mutation == 'method': bad['review_method']='model_guess'
                with self.assertRaises(ValueError): resolve(prepared, root, bad)
