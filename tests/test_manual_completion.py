from copy import deepcopy
import unittest

from trippy.research.manual_completion import materialize
from trippy.sources.extraction import fingerprint


class ManualCompletionTests(unittest.TestCase):
    def fixture(self):
        claim={'dimension':'dishes','basis':'source_fact','value':'The creator ordered coffee.',
            'observed_at':None,'citations':[{'segment_id':'video:000001','start_seconds':1,
                'end_seconds':2,'quote':'I ordered coffee.'}]}
        cid=fingerprint(claim)
        entry={'key':'slot','kind':'facet','record_id':'old','record_kind':'venue','identity_uncertain':False,
            'name':'Cafe','proposal':{'key':'service','value':'coffee','claim_ids':[cid]},
            'claims':[claim|{'id':cid}]}
        items=[{'entry':entry,'decision':{'action':'reject'}}];quarantine=[]
        registry={'facet_keys':['service'],'closed_values':{'service':['coffee']},'detail_keys':['dish_detail']}
        baseline={'previous_to_normalized_ids':{'old':'base'}}
        staged={'previous_to_staged_ids':{'base':'current'},'drafts':[{'id':'current','claims':[claim]}]}
        audit={'inputs':{'items_sha256':fingerprint(items),'quarantine_sha256':fingerprint(quarantine),
            'registry_sha256':fingerprint(registry),'baseline_sha256':fingerprint(baseline),'staged_sha256':fingerprint(staged)},
            'decisions':[{'key':'slot','entry_sha256':fingerprint(entry),'evidence_claim_ids':[cid],
                'evidence_sha256':fingerprint(entry['claims']),'review_method':'agent_exact_source_quote_comparison',
                'reason':'An explicitly ordered drink supports visit discovery, not current service availability.',
                'finding':'model_review_error','action':'retain','assertion_scope':'visit_context',
                'lifecycle':'source_description','after':None}]}
        return items,quarantine,audit,registry,baseline,staged

    def test_visit_recommendation_can_survive_overcautious_rejection(self):
        args=self.fixture();before=deepcopy(args);result=materialize(*args)
        self.assertEqual(args,before)
        self.assertTrue(result['annotations'][0]['source_discovery_eligible'])
        self.assertFalse(result['annotations'][0]['planner_fact_eligible'])
        self.assertFalse(result['ready_to_publish'])

    def test_unreviewed_model_result_never_inherits_manual_approval(self):
        args=list(self.fixture());args[2]['decisions']=[]
        result=materialize(*args)
        self.assertEqual(result['summary']['manual_review_pending'],1)
        self.assertFalse(result['annotations'][0]['source_discovery_eligible'])

    def test_changed_current_claim_does_not_inherit_old_annotation(self):
        args=list(self.fixture());args[5]['drafts'][0]['claims'][0]['value']='Different edited claim.'
        args[2]['inputs']['staged_sha256']=fingerprint(args[5]);result=materialize(*args)
        self.assertEqual(result['summary']['stale_manual_claim_bindings'],1)
        self.assertFalse(result['annotations'][0]['source_discovery_eligible'])

    def test_cross_kind_migration_preserves_quote_binding(self):
        args=list(self.fixture());d=args[2]['decisions'][0];d.update(action='replace',finding='confirmed_annotation_error',
            after={'kind':'detail','proposal':{'key':'dish_detail','value':'The creator ordered coffee.',
                'claim_ids':d['evidence_claim_ids']}})
        result=materialize(*args)
        self.assertEqual(result['annotations'][0]['effective']['kind'],'detail')
        self.assertEqual(result['summary']['source_claims_modified'],0)
        d['after']['proposal']['claim_ids']=['foreign']
        with self.assertRaises(ValueError):materialize(*args)

    def test_stale_or_duplicate_manual_decisions_fail(self):
        args=list(self.fixture());args[2]['decisions'][0]['evidence_sha256']='stale'
        with self.assertRaises(ValueError):materialize(*args)
        args=list(self.fixture());args[2]['decisions']*=2
        with self.assertRaises(ValueError):materialize(*args)

    def test_invalid_retained_closed_value_requires_explicit_migration(self):
        args=list(self.fixture());args[0][0]['entry']['proposal']['value']='invented'
        args[2]['inputs']['items_sha256']=fingerprint(args[0])
        args[2]['decisions'][0]['entry_sha256']=fingerprint(args[0][0]['entry'])
        with self.assertRaises(ValueError):materialize(*args)
