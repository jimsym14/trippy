import copy
import unittest
from tests import test_creator_extraction as fixtures
from trippy.sources.extraction import aggregate,fingerprint
from trippy.sources.curation import apply_curation


class CurationTests(unittest.TestCase):
    def fixture(self):
        chunk,raw=fixtures.ExtractionTests().fixture();report=aggregate([(chunk,raw)])
        draft=report['drafts'][0]
        decision={'draft_id':draft['id'],'before_sha256':fingerprint(draft),'action':'claim_dimension',
            'claim_sha256':fingerprint(draft['claims'][0]),'dimension':'recommendation','reviewer':'synthetic test','reason':'synthetic review'}
        return chunk,report,decision

    def test_editorial_correction_preserves_quote_and_original(self):
        chunk,report,decision=self.fixture()
        before=copy.deepcopy(report)
        result=apply_curation(report,{'chunks':[chunk]},[decision])
        self.assertEqual(report,before)
        self.assertEqual(result['drafts'][0]['claims'][0]['dimension'],'recommendation')
        self.assertEqual(result['drafts'][0]['claims'][0]['citations'],before['drafts'][0]['claims'][0]['citations'])
        self.assertEqual(result['editorial_audit'][0]['original'],before['drafts'][0])
        self.assertNotEqual(result['drafts'][0]['id'],before['drafts'][0]['id'])
        self.assertEqual(result['catalog_writes'],0)

    def test_exclusion_preserves_private_evidence(self):
        chunk,report,decision=self.fixture();decision['action']='exclude'
        result=apply_curation(report,{'chunks':[chunk]},[decision])
        self.assertFalse(result['drafts'])
        self.assertEqual(result['excluded_drafts'],report['drafts'])

    def test_stale_unsupported_and_unreviewed_edits_rejected(self):
        chunk,report,decision=self.fixture()
        for field,value in [('before_sha256','stale'),('claim_sha256','stale'),('action','rewrite_quote'),('reviewer','')]:
            changed={**decision,field:value}
            with self.subTest(field=field),self.assertRaises(ValueError):apply_curation(report,{'chunks':[chunk]},[changed])

    def test_claim_value_review_keeps_exact_quotes_and_upstream_metadata(self):
        chunk,report,decision=self.fixture()
        report['review_issues']=[{'explanation':'Unresolved source review'}]
        decision.update(action='claim_value',value='The source praises the coffee.')
        # Metadata is outside the content-bound draft being edited.
        result=apply_curation(report,{'chunks':[chunk]},[decision])
        self.assertEqual(result['drafts'][0]['claims'][0]['value'],decision['value'])
        self.assertEqual(result['editorial_audit'][0]['original'],report['drafts'][0])
        self.assertEqual(result['drafts'][0]['claims'][0]['citations'],report['drafts'][0]['claims'][0]['citations'])
        self.assertEqual(result['review_issues'],report['review_issues'])
        self.assertEqual(result['upstream_to_editorial_ids'][report['drafts'][0]['id']],result['drafts'][0]['id'])

    def test_added_claim_requires_original_evidence_and_cannot_forge_quotes(self):
        chunk,report,decision=self.fixture()
        claim=copy.deepcopy(report['drafts'][0]['claims'][0]);claim['dimension']='recommendation'
        decision.update(action='claim_add',claim=claim)
        result=apply_curation(report,{'chunks':[chunk]},[decision])
        self.assertEqual(len(result['drafts'][0]['claims']),2)
        decision['claim']['citations'][0]['quote']='invented'
        with self.assertRaises(ValueError):apply_curation(report,{'chunks':[chunk]},[decision])

    def test_additional_citations_do_not_replace_original_quotes(self):
        chunk,report,decision=self.fixture()
        citation=copy.deepcopy(report['drafts'][0]['claims'][0]['citations'][0])
        citation['quote']='serves excellent coffee in Barcelona.'
        decision.update(action='claim_citations_add',additional_citations=[citation])
        result=apply_curation(report,{'chunks':[chunk]},[decision])
        self.assertEqual(result['drafts'][0]['claims'][0]['citations'][0],report['drafts'][0]['claims'][0]['citations'][0])
        self.assertEqual(result['drafts'][0]['claims'][0]['citations'][1],citation)

    def test_claim_move_preserves_evidence_and_both_original_records(self):
        chunk,raw=fixtures.ExtractionTests().fixture()
        target=copy.deepcopy(raw['mentions'][0]);target.update(name='Example',claims=[])
        raw['mentions'].append(target);report=aggregate([(chunk,raw)])
        donor,recipient=report['drafts']
        decision={'draft_id':donor['id'],'before_sha256':fingerprint(donor),
            'action':'claim_move','claim_sha256':fingerprint(donor['claims'][0]),
            'target_draft_id':recipient['id'],'target_before_sha256':fingerprint(recipient),
            'reviewer':'test fixture','reason':'Synthetic same-source subject correction.'}
        result=apply_curation(report,{'chunks':[chunk]},[decision])
        self.assertFalse(result['drafts'][0]['claims'])
        self.assertEqual(result['drafts'][1]['claims'],donor['claims'])
        self.assertEqual(result['editorial_audit'][0]['original_target'],recipient)
        decision['target_before_sha256']='stale'
        with self.assertRaises(ValueError):apply_curation(report,{'chunks':[chunk]},[decision])


if __name__=='__main__':unittest.main()
