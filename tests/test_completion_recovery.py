from copy import deepcopy
import json
from pathlib import Path
import unittest

from tests import test_semantic_materialize as fixtures
from trippy.research.reviews import source_chunk,annotation_chunk
from trippy.research.completion_recovery import recover_request


class CompletionRecoveryTests(unittest.TestCase):
    def annotation_fixture(self):
        registry=json.loads(Path('configs/activity-registry-v1.json').read_text())
        entries=[{'key':key,'record_id':'r1','record_kind':'venue','kind':'facet',
            'proposal':{'key':'service','value':'coffee','claim_ids':['c1']},
            'claims':[{'id':'c1','value':'The speaker had coffee here.'}]} for key in ('a','b')]
        fields={'action':'retain','assertion_scope':'visit_context','lifecycle':'source_description',
            'evidence_claim_ids':['c1'],'replacement_key':None,'replacement_value':None,'reason':'Visit context only.'}
        return annotation_chunk(entries,registry),{'decisions':{key:deepcopy(fields) for key in ('a','b')}}

    def test_bad_taxonomy_slot_does_not_discard_valid_sibling(self):
        request,response=self.annotation_fixture()
        response['decisions']['b'].update(action='repair',replacement_key='service',replacement_value='invented_service')
        result=recover_request(request,response,'facets')
        self.assertEqual([i['entry']['key'] for i in result['items']],['a'])
        self.assertEqual([i['key'] for i in result['quarantine']],['b'])

    def test_redundant_replacement_clears_without_rewriting_original(self):
        request,response=self.annotation_fixture(); before=deepcopy(response)
        response['decisions']['a'].update(replacement_key='service',replacement_value='coffee')
        raw=deepcopy(response); result=recover_request(request,response,'facets')
        self.assertEqual(response,raw)
        self.assertEqual(result['items'][0]['decision']['action'],'retain')
        self.assertEqual(result['items'][0]['events'],['removed_redundant_replacement'])

    def test_context_text_suggestion_stays_separate_and_implicit_repair_is_held(self):
        request,response=self.annotation_fixture()
        response['decisions']['a'].update(action='context',replacement_key='visit_detail',replacement_value='A proposed new explanation.')
        response['decisions']['b'].update(replacement_key='service',replacement_value='specialty_coffee')
        result=recover_request(request,response,'facets')
        a,b=result['items']
        self.assertEqual(a['decision']['action'],'context');self.assertEqual(len(a['unapplied_suggestions']),1)
        self.assertEqual(b['decision']['action'],'unresolved');self.assertFalse(b['decision']['source_discovery_candidate'])

    def test_duplicate_actual_cue_recovered_but_foreign_cue_not_removed(self):
        records,cues,prepared,effective,_=fixtures.SemanticMaterializeTests().fixture()
        entry=prepared['chunks'][0]['payload']['entries'][0];request=source_chunk([entry],cues)
        d={k:v for k,v in effective['decisions'][0].items() if k not in {'key','approval','original_entry_sha256'}}
        d.update(assertion_scope='general',lifecycle='creator_opinion',subject_note='Synthetic source context.')
        d['evidence_segment_ids']*=2
        result=recover_request(request,{'decisions':{entry['key']:d}},'source')
        self.assertEqual(result['items'][0]['events'],['deduplicated_identical_evidence_references'])
        d['evidence_segment_ids'].append('foreign:000000')
        result=recover_request(request,{'decisions':{entry['key']:d}},'source')
        self.assertEqual(len(result['quarantine']),1)
