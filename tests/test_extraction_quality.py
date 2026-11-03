import copy
import tempfile
from pathlib import Path
import unittest
from tests import test_creator_extraction as fixtures
from trippy.sources.extraction import aggregate, execute_chunks, fingerprint, chunk_evidence
from trippy.sources.pilot import validate_pilot
from trippy.sources.quality import assess, require_scale_approval, metadata_observations
from trippy.sources.review import partition_mentions


class QualityTests(unittest.TestCase):
    def fixture(self):
        chunk,raw=fixtures.ExtractionTests().fixture()
        reference={'version':1,'scope':'critical_sample',
            'source_evidence_sha256':{'abcdefghijk':chunk['payload']['source_evidence_sha256']},
            'targets':[{'id':'cafe','source_id':'abcdefghijk','segments':['abcdefghijk:000000'],'anchor':'Cafe Example'}]}
        return chunk,raw,reference

    def test_exact_multi_cue_recovery_rejects_modified_or_omitted_speech(self):
        chunk,raw,_=self.fixture()
        chunk['payload']['segments']=[{'segment_id':'abcdefghijk:000000','text':'We visit Cafe',
            'start_seconds':0.,'end_seconds':2.},{'segment_id':'abcdefghijk:000001','text':'Example today.',
            'start_seconds':2.,'end_seconds':4.}]
        mention=raw['mentions'][0];mention['claims']=[]
        mention['citations'][0]['quote']='We visit Cafe Example today.'
        valid,rejected,repairs=partition_mentions(chunk,raw)
        self.assertFalse(rejected)
        self.assertEqual(len(valid['mentions'][0]['citations']),2)
        self.assertEqual(' '.join(c['quote'] for c in valid['mentions'][0]['citations']),mention['citations'][0]['quote'])
        self.assertEqual(len(repairs),1)
        bad=copy.deepcopy(raw);bad['mentions'][0]['citations'][0]['quote']='We visit Cafe Example tomorrow.'
        self.assertFalse(partition_mentions(chunk,bad)[0]['mentions'])
        chunk['payload']['segments'][1]['segment_id']='abcdefghijk:000002'
        self.assertFalse(partition_mentions(chunk,raw)[0]['mentions'])

    def test_schema_failure_does_not_discard_other_mentions(self):
        chunk,raw,_=self.fixture()
        raw['mentions'].append({'name':'Bad schema'})
        accepted,rejected,_=partition_mentions(chunk,raw)
        self.assertEqual(len(accepted['mentions']),1)
        self.assertEqual(rejected[0]['kind'],'mention_schema')

    def test_partial_cache_preserves_quarantine_and_does_not_recall_provider(self):
        chunk,raw,_=self.fixture()
        bad=copy.deepcopy(raw['mentions'][0]);bad['name']='Unsupported';raw['mentions'].append(bad)
        calls=[]
        with tempfile.TemporaryDirectory() as folder:
            for _ in range(2):
                results,errors=execute_chunks([chunk],lambda c:(calls.append(c),raw)[1],folder)
                self.assertEqual(len(results),1)
                self.assertEqual(errors[0]['error_type'],'PartialEvidenceValidation')
        self.assertEqual(len(calls),1)

    def test_coverage_is_not_semantic_approval(self):
        chunk,raw,ref=self.fixture()
        result=assess(aggregate([(chunk,raw)]),{'chunks':[chunk]},ref)
        self.assertTrue(result['gates']['benchmark_passed'])
        self.assertFalse(result['gates']['ready_to_scale_extraction'])
        self.assertFalse(result['gates']['ready_to_publish'])
        self.assertEqual(result['summary']['unreviewed_mentions'],1)

    def test_missing_place_and_wrong_dimension_fail_benchmark(self):
        chunk,raw,ref=self.fixture()
        ref['targets'][0]['dimension']='opening_hours'
        report=aggregate([(chunk,raw)])
        self.assertFalse(assess(report,{'chunks':[chunk]},ref)['gates']['benchmark_passed'])
        self.assertFalse(assess(aggregate([]),{'chunks':[chunk]},ref)['gates']['benchmark_passed'])

    def test_unanchored_reference_cross_source_and_stale_reviews_rejected(self):
        chunk,raw,ref=self.fixture();report=aggregate([(chunk,raw)])
        for mode in ('anchor','source','hash','annotation'):
            changed=copy.deepcopy(ref);annotations={}
            if mode=='anchor':changed['targets'][0]['anchor']='Made up'
            if mode=='source':changed['targets'][0]['source_id']='other'
            if mode=='hash':changed['source_evidence_sha256']['abcdefghijk']='changed'
            if mode=='annotation':annotations={'stale':{'semantic':'approved'}}
            with self.subTest(mode=mode),self.assertRaises(ValueError):assess(report,{'chunks':[chunk]},changed,annotations)

    def test_historical_hours_remain_blocked_even_with_approval(self):
        chunk,raw,ref=self.fixture()
        text='Cafe Example was founded in 1851.'
        chunk['payload']['segments'][0]['text']=text
        mention=raw['mentions'][0];mention['citations'][0]['quote']=text
        mention['claims'][0].update(dimension='opening_hours',value='Founded in 1851')
        chunk['id']=fingerprint({'prompt':chunk['system_prompt'],'schema':chunk['response_schema'],'payload':chunk['payload']})
        key=fingerprint({'source':'abcdefghijk','mention':mention})
        annotations={key:{'semantic':'approved','identity':'resolved','current_facts':'verified',
            'review_method':'manual_source_comparison','reviewer':'test fixture','reason':'synthetic annotation'}}
        ref['scope']='exhaustive_actionable_inventory'
        result=assess(aggregate([(chunk,raw)]),{'chunks':[chunk]},ref,annotations)
        self.assertEqual(result['issues'][0]['kind'],'historical_date_as_opening_hours')
        self.assertFalse(result['gates']['ready_to_scale_extraction'])

    def test_greek_idiom_literal_translation_remains_a_semantic_blocker(self):
        chunk,raw,ref=self.fixture()
        text='Cafe Example: την έχουν πατήσει πολλοί τουρίστες.'
        chunk['payload']['segments'][0]['text']=text
        mention=raw['mentions'][0];mention['citations'][0]['quote']=text
        mention['claims'][0].update(dimension='safety',value='Many tourists have stepped on them.')
        chunk['id']=fingerprint({'prompt':chunk['system_prompt'],'schema':chunk['response_schema'],'payload':chunk['payload']})
        report=aggregate([(chunk,raw)])
        result=assess(report,{'chunks':[chunk]},ref)
        self.assertTrue(any(i['kind']=='possible_greek_idiom_as_literal_trampling' for i in result['issues']))
        self.assertEqual(report['drafts'][0]['claims'][0]['citations'],mention['claims'][0]['citations'])

    def test_content_bound_source_findings_are_blockers_and_reject_stale_claims(self):
        chunk,raw,ref=self.fixture();report=aggregate([(chunk,raw)])
        draft=report['drafts'][0]
        report['source_review_findings']=[{'draft_id':draft['id'],
            'claim_sha256':fingerprint(draft['claims'][0]),'reviewer':'test',
            'review_method':'manual_source_comparison','finding':'Check the subject assignment.'}]
        result=assess(report,{'chunks':[chunk]},ref)
        self.assertEqual(result['issues'][0]['kind'],'targeted_source_review_finding')
        self.assertFalse(result['gates']['ready_to_scale_extraction'])
        report['source_review_findings'][0]['claim_sha256']='stale'
        with self.assertRaises(ValueError):assess(report,{'chunks':[chunk]},ref)

    def test_v1_and_v2_fingerprints_remain_reproducible(self):
        evidence=fixtures.ExtractionTests().evidence()
        first=chunk_evidence(evidence,prompt_version=1)[0][0]
        second=chunk_evidence(evidence,prompt_version=2)[0][0]
        self.assertNotEqual(first['id'],second['id'])
        for chunk in (first,second):validate_pilot({'version':1,'planned_calls':1,'chunks':[chunk]})
        second['system_prompt']='changed'
        with self.assertRaises(ValueError):validate_pilot({'version':1,'planned_calls':1,'chunks':[second]})

    def test_bulk_execution_requires_reviewed_same_prompt_gate(self):
        chunk,_,_=self.fixture();chunks=[chunk]*7
        with self.assertRaises(ValueError):require_scale_approval(chunks,None)
        approval={'version':1,'gates':{'ready_to_scale_extraction':True,'benchmark_passed':True},
            'summary':{'reference_targets':1,'covered_targets':1,'unreviewed_mentions':0},
            'benchmark_scope':'exhaustive_actionable_inventory','prompt_sha256':[fingerprint(chunk['system_prompt'])],
            'semantic_review_pending':[],'issues':[],'cue_review_pending':[],'uncertain_source_cues':[]}
        require_scale_approval(chunks,approval)
        approval['prompt_sha256']=['old']
        with self.assertRaises(ValueError):require_scale_approval(chunks,approval)

    def test_metadata_names_and_disclosures_do_not_become_spoken_facts(self):
        chunk,_,_=self.fixture()
        chunk['payload']['metadata']['description']='13:19 LA PINEDA\nJoin a Devour food tour!'
        observations=metadata_observations([chunk])
        self.assertEqual(len(observations),2)
        self.assertEqual(observations[0]['start_seconds'],799)
        self.assertEqual(observations[0]['value'],'LA PINEDA')
        self.assertEqual(observations[0]['citation']['field'],'metadata.description')
        self.assertIn('venue_payment_not_established',observations[1]['status'])

    def test_ambiguous_spanning_quotes_remain_rejected(self):
        chunk,raw,_=self.fixture()
        chunk['payload']['segments']=[{'segment_id':f'abcdefghijk:{n:06d}',
            'text':'Cafe' if n%2==0 else 'Example', 'start_seconds':float(n),'end_seconds':float(n+1)} for n in range(4)]
        raw['mentions'][0]['claims']=[]
        raw['mentions'][0]['citations'][0].update(segment_id='wrong',quote='Cafe Example')
        accepted,rejected,_=partition_mentions(chunk,raw)
        self.assertFalse(accepted['mentions'])
        self.assertEqual(rejected[0]['kind'],'mention')

    def test_partial_reference_cannot_approve_scaling_even_when_reviewed(self):
        chunk,raw,ref=self.fixture()
        mention=raw['mentions'][0];key=fingerprint({'source':'abcdefghijk','mention':mention})
        annotation={key:{'semantic':'approved','review_method':'manual_source_comparison',
            'reviewer':'synthetic test','reason':'test only'}}
        report=assess(aggregate([(chunk,raw)]),{'chunks':[chunk]},ref,annotation)
        self.assertTrue(report['gates']['benchmark_passed'])
        self.assertFalse(report['gates']['ready_to_scale_extraction'])

    def test_wrong_price_is_flagged_despite_valid_quote(self):
        chunk,raw,ref=self.fixture();text='Cafe Example costs three euros.'
        chunk['payload']['segments'][0]['text']=text
        raw['mentions'][0]['citations'][0]['quote']=text
        raw['mentions'][0]['claims'][0].update(dimension='price',value='Costs 999 euros')
        chunk['id']=fingerprint({'prompt':chunk['system_prompt'],'schema':chunk['response_schema'],'payload':chunk['payload']})
        report=assess(aggregate([(chunk,raw)]),{'chunks':[chunk]},ref)
        self.assertEqual(report['issues'][0]['kind'],'numeric_price_not_in_cited_speech')
        raw['mentions'][0]['claims'][0]['value']='Costs 3.00 euros'
        self.assertFalse(assess(aggregate([(chunk,raw)]),{'chunks':[chunk]},ref)['issues'])


if __name__=='__main__':unittest.main()
