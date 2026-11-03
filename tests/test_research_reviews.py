from copy import deepcopy
import json
from pathlib import Path
import unittest

from trippy.research.reviews import annotation_chunk, validate_annotations


class ResearchReviewTests(unittest.TestCase):
    def fixture(self):
        registry=json.loads(Path('configs/activity-registry-v1.json').read_text())
        entry={'key':'annotation1','record_id':'r1','record_kind':'venue','kind':'facet',
               'proposal':{'key':'service','value':'coffee','claim_ids':['c1']},
               'claims':[{'id':'c1','value':'General history of granjas.'}]}
        fields={'action':'context','assertion_scope':'general','lifecycle':'source_description',
            'evidence_claim_ids':['c1'],'replacement_key':None,'replacement_value':None,
            'reason':'General granja history does not prove a particular venue service.'}
        return entry,registry,fields

    def test_general_context_and_nonvenue_records_never_become_venue_candidates(self):
        entry,registry,fields=self.fixture()
        result=validate_annotations(annotation_chunk([entry],registry),{'decisions':{'annotation1':fields}})
        self.assertFalse(result['decisions'][0]['source_discovery_candidate'])
        entry['record_kind']='district'; fields.update(action='retain',assertion_scope='exact_venue')
        result=validate_annotations(annotation_chunk([entry],registry),{'decisions':{'annotation1':fields}})
        self.assertFalse(result['decisions'][0]['source_discovery_candidate'])
        self.assertFalse(result['decisions'][0]['planner_fact_eligible'])

    def test_cross_record_evidence_missing_slots_and_silent_repair_are_rejected(self):
        entry,registry,fields=self.fixture(); request=annotation_chunk([entry],registry)
        for change in ({'evidence_claim_ids':['foreign']},{'replacement_value':'specialty'},
                       {'evidence_claim_ids':[]},{'reason':['not a string']}):
            with self.subTest(change=change),self.assertRaises(ValueError):
                validate_annotations(request,{'decisions':{'annotation1':fields|change}})
        with self.assertRaises(ValueError): validate_annotations(request,{'decisions':{}})

    def test_unsupported_taxonomy_is_not_admitted_by_retaining_a_proposal(self):
        entry,registry,fields=self.fixture(); entry['taxonomy_admission_pending']=True
        entry['proposal']['value']='unsupported_service'
        fields.update(action='retain',assertion_scope='exact_venue')
        result=validate_annotations(annotation_chunk([entry],registry),{'decisions':{'annotation1':fields}})
        self.assertFalse(result['decisions'][0]['source_discovery_candidate'])
        fields.update(action='repair',replacement_key='service',replacement_value='unsupported_service')
        with self.assertRaises(ValueError): validate_annotations(annotation_chunk([entry],registry),{'decisions':{'annotation1':fields}})
