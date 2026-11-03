from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest

from tests import test_dataset_integration as fixtures
from trippy.research.dataset_integration import integrate, write_snapshot
from trippy.research.dataset_audit import audit
from trippy.sources.extraction import fingerprint


class DatasetAuditTests(unittest.TestCase):
    def run_fixture(self, mutate=None):
        args = fixtures.DatasetIntegrationTests().fixture()
        bundle = integrate(*args)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            recipe = {}
            for key, value in [('pack', args[0]), ('held', args[1]), ('annotations', args[6]),
                               ('identity_links', args[7]), ('operational', args[8])]:
                path = root / (key+'.json')
                path.write_text(json.dumps(value))
                recipe[key] = str(path)
            database = root/'dataset.sqlite'
            write_snapshot(database, bundle)
            modified = deepcopy(bundle)
            if mutate:
                mutate(modified)
            path = root/'dataset.json'
            path.write_text(json.dumps(modified))
            return audit({'dataset': str(path), 'database': str(database),
                          'bundle_sha256': fingerprint(modified)}, recipe)

    def test_audit_preserves_scope_despite_full_admission(self):
        result = self.run_fixture()
        self.assertEqual(result['source_slots'], 1)
        self.assertEqual(result['readiness']['after_percent'], 100)
        self.assertFalse(result['readiness']['planner_ready'])

    def test_deleted_source_occurrence_is_detected(self):
        def delete(bundle):
            bundle['normalized']['drafts'][0]['claim_review_metadata'] = []
        with self.assertRaisesRegex(ValueError, 'Lost or invented'):
            self.run_fixture(delete)

    def test_record_context_loss_is_detected_even_if_claims_survive(self):
        def delete(bundle):
            bundle['normalized']['drafts'][0]['name'] = 'wrong subject'
        with self.assertRaisesRegex(ValueError, 'record metadata changed'):
            self.run_fixture(delete)
