from copy import deepcopy
import unittest

from trippy.sources.extraction import fingerprint
from trippy.sources.scoped_annotations import materialize


class ScopedAnnotationTests(unittest.TestCase):
    def fixture(self):
        claim = {'value': 'General bodega history.'}
        cid = fingerprint(claim); source_claim = {'id': cid, **claim}
        facet = {'key': 'service', 'value': 'drinks', 'claim_ids': [cid]}
        proposals = {'manifest': {'input': 'synthetic'}, 'chunks': [{
            'source_entries': [{'record_id': 'old', 'claims': [source_claim]}],
            'response': {'records': {'old': {'facets': [facet]}}}}]}
        audit = {'upstream_manifest_sha256': fingerprint(proposals['manifest']),
            'reviews': [{'record_id': 'old', 'facet_sha256': fingerprint(facet),
                'facet': facet, 'source_claims': [source_claim], 'status': 'context_only',
                'review_method': 'agent_exact_source_quote_comparison'}]}
        pack = {'previous_to_normalized_ids': {'old': 'new'},
                'drafts': [{'id': 'new', 'claims': [claim]}]}
        return proposals, deepcopy(audit), pack

    def test_general_context_never_becomes_a_venue_filter(self):
        result = materialize(*self.fixture()); review = result['reviews'][0]
        self.assertEqual(review['assertion_scope'], 'general_or_area')
        self.assertTrue(review['claim_binding_current'])
        self.assertFalse(review['source_discovery_eligible'])
        self.assertFalse(review['planner_fact_eligible'])

    def test_changed_claim_requires_new_review_even_if_source_was_supported(self):
        args = self.fixture(); args[1]['reviews'][0]['status'] = 'source_supported_with_qualifier'
        self.assertTrue(materialize(*args)['reviews'][0]['source_discovery_eligible'])
        args[2]['drafts'][0]['claims'][0]['value'] = 'Edited claim.'
        review = materialize(*args)['reviews'][0]
        self.assertFalse(review['claim_binding_current'])
        self.assertFalse(review['source_discovery_eligible'])
        self.assertEqual(review['gate'], 'changed_claim_requires_new_annotation_review')

    def test_stale_review_and_duplicate_review_rejected(self):
        args = self.fixture(); args[1]['reviews'][0]['source_claims'][0]['value'] = 'Changed evidence.'
        with self.assertRaises(ValueError): materialize(*args)
        args = self.fixture(); args[1]['reviews'].append(deepcopy(args[1]['reviews'][0]))
        with self.assertRaises(ValueError): materialize(*args)
