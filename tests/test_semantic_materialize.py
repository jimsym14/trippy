from copy import deepcopy
from tempfile import TemporaryDirectory
import unittest

from tests import test_curation_cycle as fixtures
from trippy.sources.extraction import fingerprint
from trippy.sources.semantic_review import prepare, validate_review
from trippy.sources.semantic_materialize import materialize, write_artifact


class SemanticMaterializeTests(unittest.TestCase):
    def fixture(self):
        records,cues,_ = fixtures.CurationCycleTests().fixture()
        prepared = prepare(records,cues); entry = prepared['chunks'][0]['payload']['entries'][0]
        decision = {'key':entry['key'], 'action':'repair', 'dimension':'vibe',
            'value':'Synthetic explicitly compared correction.', 'basis':'creator_opinion',
            'evidence_segment_ids':[entry['claim']['citations'][0]['segment_id']],
            'use_scope':'discovery_context', 'reason':'Synthetic source comparison.'}
        reviewed = validate_review(prepared['chunks'][0], {'decisions':[decision]})
        effective = {'prepared_sha256':fingerprint(prepared), 'decisions':reviewed['decisions']}
        manual = {'review_method':'agent_source_comparison','decisions':reviewed['decisions']}
        return records,cues,prepared,effective,manual

    def test_model_proposals_are_held_and_originals_preserved(self):
        records,cues,p,e,m = self.fixture(); before = deepcopy(records)
        result = materialize(records,cues,p,e,[])
        self.assertEqual(result['summary']['active_source_claims'],0)
        self.assertEqual(result['held_claims'][0]['state'],'held_repair_proposal')
        self.assertEqual(result['held_claims'][0]['original_claim'],records[0]['claims'][0])
        self.assertEqual(records,before)
        self.assertFalse(result['summary']['planner_ready'])

    def test_only_bound_manual_repairs_apply_with_exact_evidence_and_replay(self):
        records,cues,p,e,m = self.fixture()
        result = materialize(records,cues,p,e,[m])
        self.assertEqual(result['summary']['states']['source_repair_applied'],1)
        claim = result['normalized']['drafts'][0]['claims'][0]
        self.assertEqual(claim['value'],m['decisions'][0]['value'])
        self.assertEqual(claim['citations'][0]['quote'],cues[claim['citations'][0]['segment_id']]['text'])
        self.assertEqual(result['editorial_events'][0]['original_claim'],records[0]['claims'][0])
        self.assertEqual(materialize(records,cues,p,e,[m]),result)
        with TemporaryDirectory() as root:
            folder=write_artifact(root,result)
            self.assertEqual(write_artifact(root,result),folder)
        for mutation in ('stale','duplicate','cross_source','method'):
            bad=deepcopy(m)
            if mutation=='stale':bad['decisions'][0]['original_entry_sha256']='stale'
            if mutation=='duplicate':bad['decisions'] *= 2
            if mutation=='cross_source':bad['decisions'][0]['evidence_segment_ids']=['other:000000']
            if mutation=='method':bad['review_method']='model_guess'
            with self.assertRaises(ValueError):materialize(records,cues,p,e,[bad])

    def test_supported_claim_retained_and_unresolved_claim_held(self):
        records,cues,p,e,m = self.fixture()
        d=e['decisions'][0]; d.update(action='supported',dimension=None,value=None,basis=None)
        result=materialize(records,cues,p,e,[])
        self.assertEqual(result['normalized']['drafts'][0]['claims'][0],records[0]['claims'][0])
        d.update(action='unresolved',use_scope='research_only')
        result=materialize(records,cues,p,e,[])
        self.assertEqual(result['held_claims'][0]['state'],'held_unresolved')
        self.assertEqual(result['summary']['claims_preserved_in_active_or_held'],1)
