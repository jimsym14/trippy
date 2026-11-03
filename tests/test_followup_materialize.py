from copy import deepcopy
import unittest

from tests import test_semantic_materialize as fixtures
from trippy.sources.extraction import fingerprint
from trippy.sources.semantic_materialize import materialize as initial_materialize
from trippy.sources.followup_materialize import materialize


class FollowupTests(unittest.TestCase):
    def fixture(self):
        records, cues, prepared, effective, _ = fixtures.SemanticMaterializeTests().fixture()
        initial = initial_materialize(records, cues, prepared, effective, [])
        pack, held = initial['normalized'], initial['held_claims']
        handoff = {'prepared_sha256': fingerprint(prepared)}
        decision = deepcopy(effective['decisions'][0])
        decision.update(assertion_scope='general', lifecycle='creator_opinion',
                        subject_note='General source advice, not a venue capability.')
        document = {'review_method': 'agent_expanded_source_comparison',
            'bindings': {'pack_sha256': fingerprint(pack), 'held_sha256': fingerprint(held),
                'prepared_sha256': fingerprint(prepared), 'handoff_sha256': fingerprint(handoff)},
            'decisions': [decision]}
        return pack, held, prepared, handoff, cues, document

    def test_repair_conserves_lineage_scope_and_inputs(self):
        args = self.fixture(); before = deepcopy(args)
        result = materialize(*args)
        self.assertEqual(args, before)
        self.assertEqual(result['summary']['claims_preserved_in_active_or_held'], 1)
        self.assertEqual(result['summary']['held_claims'], 0)
        metadata = result['normalized']['drafts'][0]['claim_review_metadata'][0]
        self.assertEqual(metadata['assertion_scope'], 'general')
        self.assertFalse(metadata['planner_fact_eligible'])
        self.assertFalse(metadata['canonical_identity_verified'])
        self.assertEqual(materialize(*args), result)

    def test_supported_preserves_text_and_unresolved_preserves_record_identity(self):
        args = self.fixture(); d = args[-1]['decisions'][0]
        d.update(action='supported', dimension=None, value=None, basis=None)
        result = materialize(*args)
        self.assertEqual(result['normalized']['drafts'][0]['claims'][0], args[1][0]['original_claim'])
        d.update(action='unresolved', use_scope='research_only')
        result = materialize(*args)
        self.assertEqual(result['normalized']['drafts'], args[0]['drafts'])
        self.assertEqual(result['summary']['held_claims'], 1)

    def test_rejects_stale_duplicate_cross_source_and_implicit_promotions(self):
        for case in ('binding', 'context', 'duplicate', 'foreign', 'scope', 'method', 'promotion', 'empty'):
            args = deepcopy(self.fixture()); document = args[-1]; d = document['decisions'][0]
            if case == 'binding': document['bindings']['held_sha256'] = 'stale'
            if case == 'context': d['original_entry_sha256'] = 'stale'
            if case == 'duplicate': document['decisions'].append(deepcopy(d))
            if case == 'foreign': d['evidence_segment_ids'] = ['foreign:000001']
            if case == 'scope': d['assertion_scope'] = 'anything'
            if case == 'method': document['review_method'] = 'model_agreement'
            if case == 'promotion': d.update(action='unresolved',dimension=None,value=None,basis=None)
            if case == 'empty': d['evidence_segment_ids'] = []
            with self.subTest(case=case), self.assertRaises(ValueError): materialize(*args)


if __name__ == '__main__': unittest.main()
