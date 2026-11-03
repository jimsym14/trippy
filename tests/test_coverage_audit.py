import copy
from pathlib import Path
import tempfile
import unittest
from tests import test_creator_extraction as fixtures
from trippy.sources.extraction import aggregate
from trippy.sources.coverage import prepare,prepare_final,validate_prepared,validate_audit,execute,merge,check,retain_unresolved_cues


class CoverageAuditTests(unittest.TestCase):
    def fixture(self):
        chunk,raw=fixtures.ExtractionTests().fixture();base=aggregate([(chunk,raw)])
        prepared=prepare(base,{'chunks':[chunk]});plan=prepared['chunks'][0]
        ref=plan['payload']['existing_claims'][0]['ref'];target=base['drafts'][0]['id']
        candidate={'additions':[],'new_mentions':[],'relationships':[],'issues':[],
            'coverage_groups':[{'segment_ids':['abcdefghijk:000000'],'classification':'covered','references':[ref],'reason':'Existing claim cites this cue.'}]}
        return base,prepared,plan,candidate,target

    def test_complete_evidence_accounting_is_not_fact_approval(self):
        base,prepared,plan,candidate,_=self.fixture()
        audit=validate_audit(plan,candidate)
        self.assertTrue(audit['cue_accounting_complete'])
        report=merge(base,prepared,[(plan,audit)])
        self.assertFalse(report['ready_to_scale']);self.assertFalse(report['ready_to_publish'])

    def test_missing_duplicate_unknown_and_uncited_groups_fail_accounting(self):
        _,_,plan,candidate,_=self.fixture()
        for mode in ('missing','duplicate','unknown','badref'):
            bad=copy.deepcopy(candidate)
            if mode=='missing':bad['coverage_groups']=[]
            if mode=='duplicate':bad['coverage_groups']*=2
            if mode=='unknown':bad['coverage_groups'][0]['segment_ids']=['other:000000']
            if mode=='badref':bad['coverage_groups'][0]['references']=['claim:invented']
            with self.subTest(mode=mode):self.assertFalse(validate_audit(plan,bad)['cue_accounting_complete'])

    def test_forged_addition_cannot_satisfy_coverage(self):
        _,_,plan,candidate,target=self.fixture()
        claim=copy.deepcopy(plan['payload']['existing_claims'][0]['claim'])
        claim['citations'][0]['quote']='Invented quote'
        candidate['additions']=[{'target_id':target,'association_citations':plan['payload']['entity_registry'][0]['citations'],'claims':[claim]}]
        candidate['coverage_groups'][0].update(classification='added',references=['addition:0'])
        result=validate_audit(plan,candidate)
        self.assertFalse(result['additions']);self.assertEqual(len(result['quarantine']),1)
        self.assertFalse(result['cue_accounting_complete'])

    def test_valid_addition_preserves_base_and_exact_evidence(self):
        base,prepared,plan,candidate,target=self.fixture();original=copy.deepcopy(base)
        claim=copy.deepcopy(plan['payload']['existing_claims'][0]['claim']);claim['dimension']='recommendation'
        candidate['additions']=[{'target_id':target,'association_citations':plan['payload']['entity_registry'][0]['citations'],'claims':[claim]}]
        candidate['coverage_groups'][0].update(classification='added',references=['addition:0'])
        audit=validate_audit(plan,candidate)
        self.assertTrue(audit['cue_accounting_complete'])
        report=merge(base,prepared,[(plan,audit)])
        self.assertEqual(base,original);self.assertEqual(report['summary']['merged_claims'],2)
        self.assertEqual(report['drafts'][0]['claims'][1]['citations'],claim['citations'])

    def test_cross_source_and_unknown_targets_quarantined(self):
        _,_,plan,candidate,_=self.fixture()
        claim=copy.deepcopy(plan['payload']['existing_claims'][0]['claim'])
        candidate['additions']=[{'target_id':'foreign','association_citations':claim['citations'],'claims':[claim]}]
        self.assertFalse(validate_audit(plan,candidate)['additions'])

    def test_cache_revalidates_without_another_model_call(self):
        base,prepared,_,candidate,_=self.fixture();calls=[]
        with tempfile.TemporaryDirectory() as folder:
            for _ in range(2):
                result=execute(prepared,base,lambda c:(calls.append(c),candidate)[1],folder)
                self.assertFalse(result['execution_failures'])
        self.assertEqual(len(calls),1)

    def test_changed_base_payload_and_prompt_rejected(self):
        base,prepared,_,_,_=self.fixture()
        changed=copy.deepcopy(base);changed['drafts'][0]['name']='changed'
        with self.assertRaises(ValueError):validate_prepared(prepared,changed)
        prepared['chunks'][0]['payload']['segments'][0]['text']='changed'
        with self.assertRaises(ValueError):validate_prepared(prepared,base)

    def test_review_issue_never_rewrites_existing_claim(self):
        base,prepared,plan,candidate,_=self.fixture()
        ref=plan['payload']['existing_claims'][0]['ref']
        candidate['issues']=[{'kind':'semantic_mismatch','target_refs':[ref],
            'explanation':'Review the interpretation.','citations':plan['payload']['existing_claims'][0]['claim']['citations']}]
        report=merge(base,prepared,[(plan,validate_audit(plan,candidate))])
        self.assertEqual(report['drafts'][0]['claims'],base['drafts'][0]['claims'])
        self.assertEqual(len(report['review_issues']),1)

    def test_only_exact_registry_issue_ids_can_be_repaired(self):
        _,_,plan,candidate,target=self.fixture()
        issue={'kind':'transcription_uncertain','target_refs':[target],
            'explanation':'Review the spoken name.',
            'citations':plan['payload']['entity_registry'][0]['citations']}
        candidate['issues']=[issue]
        audit=validate_audit(plan,candidate)
        self.assertEqual(audit['issues'][0]['target_refs'],['mention:'+target])
        self.assertEqual(audit['reference_repairs'][0]['original'],target)
        candidate['issues'][0]['target_refs']=['invented-id']
        self.assertFalse(validate_audit(plan,candidate)['issues'])

    def test_overlap_disagreement_and_exclusions_remain_reviewable(self):
        _,prepared,plan,candidate,_=self.fixture()
        first=validate_audit(plan,candidate)
        second=copy.deepcopy(first)
        second['coverage_groups'][0].update(classification='non_research',references=[])
        report=check(prepared,[(plan,first),(plan,second)])
        self.assertEqual(len(report['overlap_disposition_conflicts']),1)
        self.assertFalse(report['cue_accounting_complete'])
        self.assertFalse(report['semantic_approved'])
        self.assertTrue(any(i.get('classification')=='non_research' for i in report['review_queue']))

    def test_missing_cached_response_is_an_explicit_failure(self):
        base,prepared,_,_,_=self.fixture()
        def unavailable(chunk):raise ValueError('Offline: missing cache')
        with tempfile.TemporaryDirectory() as folder:
            report=execute(prepared,base,unavailable,folder)
        self.assertEqual(len(report['execution_failures']),1)
        self.assertEqual(len(report['final_check']['missing_chunk_ids']),1)
        self.assertFalse(report['final_check']['cue_accounting_complete'])

    def test_final_windows_deduplicate_core_and_preserve_original_evidence(self):
        base,_,plan,_,_=self.fixture()
        chunk,_=fixtures.ExtractionTests().fixture()
        extraction={'chunks':[chunk,copy.deepcopy(chunk)]}
        original=copy.deepcopy(extraction)
        final=prepare_final(base,extraction,core_cues=10)
        self.assertEqual(len(final['chunks']),1)
        payload=final['chunks'][0]['payload']
        self.assertEqual(payload['segments'],chunk['payload']['segments'])
        self.assertTrue(payload['cue_evidence_refs']['abcdefghijk:000000'])
        self.assertEqual(extraction,original)
        self.assertEqual(final['model_calls'],0)
        self.assertFalse(final['ready_to_scale'])
        validate_prepared(final,base)

    def test_unknown_prompt_revision_is_rejected(self):
        base,prepared,_,_,_=self.fixture()
        prepared['chunks'][0]['prompt_version']='unknown'
        with self.assertRaises(ValueError):validate_prepared(prepared,base)

    def test_final_feedback_is_bound_to_exact_base_and_claim(self):
        from trippy.sources.extraction import fingerprint
        base,_,_,_,_=self.fixture();chunk,_=fixtures.ExtractionTests().fixture()
        draft=base['drafts'][0];claim=draft['claims'][0]
        findings={'report_sha256':fingerprint(base),'findings':[{
            'draft_id':draft['id'],'claim_sha256':fingerprint(claim),
            'claim_value':claim['value'],'citations':claim['citations'],
            'finding':'Check the field assignment.'}]}
        final=prepare_final(base,{'chunks':[chunk]},review_findings=findings)
        self.assertEqual(len(final['chunks'][0]['payload']['review_feedback']),1)
        findings['findings'][0]['claim_value']='invented replacement'
        with self.assertRaises(ValueError):prepare_final(base,{'chunks':[chunk]},review_findings=findings)

    def test_uncertain_cue_cannot_hide_detail_without_an_evidence_issue(self):
        _,_,plan,candidate,_=self.fixture()
        candidate['coverage_groups'][0].update(classification='uncertain',references=[])
        audit=validate_audit(plan,candidate)
        self.assertFalse(audit['cue_accounting_complete'])
        candidate['issues']=[{'kind':'transcription_uncertain','target_refs':[],
            'explanation':'The wording needs source review.',
            'citations':plan['payload']['entity_registry'][0]['citations']}]
        candidate['coverage_groups'][0]['references']=['issue:0']
        self.assertTrue(validate_audit(plan,candidate)['cue_accounting_complete'])

    def test_keyed_schema_and_validator_require_exact_core_ids(self):
        base,_,_,candidate,_=self.fixture();chunk,_=fixtures.ExtractionTests().fixture()
        final=prepare_final(base,{'chunks':[chunk]},keyed_coverage=True)
        plan=final['chunks'][0];validate_prepared(final,base)
        keys=plan['response_schema']['properties']['cue_coverage']['required']
        self.assertEqual(keys,['abcdefghijk:000000'])
        group=candidate.pop('coverage_groups')[0]
        group.pop('segment_ids');candidate['cue_coverage']={keys[0]:group}
        self.assertTrue(validate_audit(plan,candidate)['cue_accounting_complete'])
        for mutation in ('missing','context','override'):
            bad=copy.deepcopy(candidate)
            if mutation=='missing':bad['cue_coverage']={}
            if mutation=='context':bad['cue_coverage']['abcdefghijk:999999']=group
            if mutation=='override':bad['cue_coverage'][keys[0]]['segment_ids']=['fake']
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):validate_audit(plan,bad)

    def test_local_registry_anchor_repair_never_invents_a_name(self):
        _,_,plan,candidate,target=self.fixture()
        claim=copy.deepcopy(plan['payload']['existing_claims'][0]['claim'])
        claim['dimension']='recommendation'
        association=copy.deepcopy(claim['citations'])
        association[0]['quote']='serves excellent coffee in Barcelona.'
        candidate['additions']=[{'target_id':target,'association_citations':association,'claims':[claim]}]
        result=validate_audit(plan,candidate)
        self.assertEqual(len(result['additions']),1)
        self.assertTrue(any(r.get('kind')=='local_identity_anchor_appended' for r in result['citation_repairs']))
        plan['payload']['entity_registry'][0]['citations'][0]['segment_id']='outside-window'
        self.assertFalse(validate_audit(plan,candidate)['additions'])

    def test_partial_evaluation_preserves_full_base_and_preflights_evidence(self):
        from trippy.sources.extraction import fingerprint
        first,raw=fixtures.ExtractionTests().fixture()
        second=copy.deepcopy(first);other=copy.deepcopy(raw)
        second['payload']['source']['external_id']='lmnopqrstuv'
        second['payload']['segments'][0]['segment_id']='lmnopqrstuv:000000'
        for q in other['mentions'][0]['citations']+other['mentions'][0]['claims'][0]['citations']:
            q['segment_id']='lmnopqrstuv:000000'
        second['id']=fingerprint({'prompt':second['system_prompt'],'schema':second['response_schema'],'payload':second['payload']})
        original={'chunks':[first,second]};base=aggregate([(first,raw),(second,other)])
        prepared=prepare_final(base,original);prepared['chunks']=prepared['chunks'][:1]
        payload=prepared['chunks'][0]['payload']
        candidate={'additions':[],'new_mentions':[],'relationships':[],'issues':[],
            'coverage_groups':[{'segment_ids':['abcdefghijk:000000'],'classification':'covered',
                'references':[payload['existing_claims'][0]['ref']],'reason':'Existing exact evidence.'}]}
        calls=[]
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):execute(prepared,base,lambda c:calls.append(c),folder)
            self.assertFalse(calls)
            result=execute(prepared,base,lambda c:candidate,folder,original_extraction=original)
        self.assertEqual(len(result['drafts']),2)
        self.assertFalse(result['execution_failures'])

    def test_invalid_claim_does_not_discard_supported_sibling(self):
        _,_,plan,candidate,target=self.fixture()
        valid=copy.deepcopy(plan['payload']['existing_claims'][0]['claim'])
        valid['dimension']='recommendation'
        invalid=copy.deepcopy(valid);invalid['citations'][0]['quote']='Invented evidence'
        candidate['additions']=[{'target_id':target,
            'association_citations':plan['payload']['entity_registry'][0]['citations'],
            'claims':[invalid,valid]}]
        result=validate_audit(plan,candidate)
        self.assertEqual(result['additions'][0]['claims'],[valid])
        self.assertEqual(len(result['quarantine']),1)
        self.assertEqual(result['quarantine'][0]['parent_ref'],'addition:0')

    def test_failed_coverage_retains_exact_cue_as_uncertain_not_a_fact(self):
        base,_,_,_,_=self.fixture();chunk,_=fixtures.ExtractionTests().fixture()
        final=prepare_final(base,{'chunks':[chunk]},keyed_coverage=True);plan=final['chunks'][0]
        raw={'additions':[],'new_mentions':[],'relationships':[],'issues':[],
            'cue_coverage':{'abcdefghijk:000000':{'classification':'covered','references':['invented'],
                'reason':'Bad reference'}}};original=copy.deepcopy(raw)
        audit,lineage=retain_unresolved_cues(plan,raw)
        self.assertEqual(raw,original);self.assertTrue(audit['cue_accounting_complete'])
        self.assertFalse(audit['additions']);self.assertFalse(audit['new_mentions'])
        self.assertEqual(audit['coverage_groups'][0]['classification'],'uncertain')
        self.assertEqual(audit['issues'][0]['citations'][0]['quote'],plan['payload']['segments'][0]['text'])
        self.assertEqual(len(lineage['adjustments']),1)
        self.assertFalse(check(final,[(plan,audit)])['semantic_approved'])


if __name__=='__main__':unittest.main()
