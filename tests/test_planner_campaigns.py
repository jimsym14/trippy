from copy import deepcopy
from decimal import Decimal
from tempfile import TemporaryDirectory
from unittest.mock import patch
import unittest

from tests import test_semantic_review as fixtures
from tests import test_curation_cycle as source_fixtures
from trippy.sources.extraction import fingerprint
from trippy.sources.luna import BudgetError
from trippy.sources.planner_campaigns import prepare_followup, research_campaigns
from trippy.sources.semantic_review import prepare, validate_review, execute


class PlannerCampaignTests(unittest.TestCase):
    def fixture(self):
        records,cues,_=source_fixtures.CurationCycleTests().fixture()
        baseline=prepare(records,cues);entry=baseline['chunks'][0]['payload']['entries'][0]
        decision={'key':entry['key'],'action':'unresolved','dimension':None,'value':None,
            'basis':None,'evidence_segment_ids':[entry['claim']['citations'][0]['segment_id']],
            'use_scope':'research_only','reason':'Synthetic missing-context review.'}
        decision=validate_review(baseline['chunks'][0],{'decisions':[decision]})['decisions'][0]
        held=[{'key':entry['key'],'original_claim':entry['claim'],'adjudication':{'decision':decision}}]
        return held,baseline,records,cues

    def test_followup_is_bound_and_every_slot_has_its_own_evidence_enum(self):
        held,p,records,cues=self.fixture();before=deepcopy(held)
        result=prepare_followup(held,p,records,cues)
        self.assertEqual(held,before);self.assertEqual(result['claim_occurrences'],1)
        self.assertEqual(result,prepare_followup(held,p,records,cues))
        chunk=result['chunks'][0];entry=chunk['payload']['entries'][0]
        self.assertEqual(entry['upstream_entry_sha256'],held[0]['adjudication']['decision']['original_entry_sha256'])
        for definition in chunk['response_schema']['$defs'].values():
            if definition['type']=='array':
                self.assertEqual(definition['items']['enum'],entry['context_segment_ids'])
            else:
                ref=definition['properties']['evidence_segment_ids']['$ref'].rsplit('/',1)[1]
                self.assertEqual(chunk['response_schema']['$defs'][ref]['items']['enum'],entry['context_segment_ids'])

    def test_changed_duplicate_or_foreign_context_is_rejected(self):
        held,p,records,cues=self.fixture()
        for mutation in ('changed','duplicate','foreign'):
            bad=deepcopy(held)
            if mutation=='changed':bad[0]['original_claim']['value']='different'
            if mutation=='duplicate':bad*=2
            if mutation=='foreign':bad[0]['adjudication']['decision']['evidence_segment_ids']=['other:000001']
            with self.assertRaises(ValueError):prepare_followup(bad,p,records,cues)

    def test_campaigns_keep_private_scope_and_shared_budget_pools(self):
        profile={'source_languages':['el','en'],'primary_source_languages':['es','ca'],
            'coverage_cells':[{'id':'coffee','scope':'shared','queries':['{city} official coffee'],
                              'required_gates':['identity']},
                              {'id':'user_links','scope':'private_trip','queries':['{city} lodging'],
                               'required_gates':['private_inputs']}]}
        result=research_campaigns(profile,{'cases':[{'id':1}]},upstream_run_id='source-v1')
        self.assertEqual(result['campaigns'][0]['research_queries'],['Barcelona official coffee'])
        self.assertEqual(result['campaigns'][1]['execution_state'],'requires_private_or_trip_specific_inputs')
        self.assertEqual(result['campaigns'][0]['budget_pool'],'shared_gap_research')
        self.assertEqual(result['budget_allocations']['shared_gap_research'],'3.00')
        self.assertFalse(result['publication_ready'])

    def test_runner_uses_separate_task_group_but_preserves_shared_cap(self):
        chunk,response=fixtures.SemanticReviewTests().fixture()
        p={'claim_occurrences':len(response['decisions']),'chunks':[chunk]}
        values={'TRIPPY_AI_BUDGET_AMOUNT':'15','TRIPPY_AI_BUDGET_CURRENCY':'USD',
                'TRIPPY_LUNA_INPUT_PER_MILLION':'.30','TRIPPY_LUNA_OUTPUT_PER_MILLION':'1'}
        with TemporaryDirectory() as root, patch('trippy.sources.semantic_review.ledger_state',return_value=('USD',Decimal('1'),Decimal('0'))) as ledger, patch('trippy.sources.semantic_review.request_with_deadline',return_value=response) as provider:
            status=execute(p,values,'ledger',root,task_cap=Decimal('1.25'),request_group='targeted-test',output_tokens=5000)
            self.assertTrue(status['complete']);ledger.assert_called_with('ledger','targeted-test')
            sent=provider.call_args.args[0]
            self.assertEqual(sent['TRIPPY_LUNA_REQUEST_GROUP'],'targeted-test')
            self.assertEqual(sent['TRIPPY_LUNA_MAX_OUTPUT_TOKENS'],'5000')
        with TemporaryDirectory() as root, patch('trippy.sources.semantic_review.ledger_state',return_value=('USD',Decimal('14.999'),Decimal('0'))), patch('trippy.sources.semantic_review.request_with_deadline') as provider:
            with self.assertRaises(BudgetError):execute(p,values,'ledger',root,request_group='targeted-test',output_tokens=5000)
            provider.assert_not_called()
