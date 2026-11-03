from copy import deepcopy
import unittest
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from trippy.sources.semantic_review import prepare, validate_review, recover_review, load_review_cache, execute, ProviderReview, adopt_saved_candidates, response_as_list, semantic_worker
from trippy.sources.extraction import fingerprint
from tests import test_curation_cycle as fixtures


class SemanticReviewTests(unittest.TestCase):
    def fixture(self):
        records, cues, _ = fixtures.CurationCycleTests().fixture()
        chunk = prepare(records, cues)['chunks'][0]
        decisions = [{'key': e['key'], 'action': 'supported', 'dimension': None, 'value': None,
            'basis': None, 'evidence_segment_ids': [e['context_segment_ids'][0]],
            'use_scope': 'discovery_context', 'reason': 'Synthetic source comparison.'}
            for e in chunk['payload']['entries']]
        return chunk, {'decisions': decisions}

    def test_missing_duplicate_and_unknown_claim_dispositions_rejected(self):
        chunk, response = self.fixture()
        for decisions in ([], response['decisions']*2,
                          [{**response['decisions'][0], 'key': 'invented'}]):
            with self.assertRaises(ValueError): validate_review(chunk, {'decisions': decisions})

    def test_model_cannot_fabricate_cues_or_silently_change_supported_claim(self):
        chunk, response = self.fixture()
        for field, value in (('evidence_segment_ids', ['other-video:000000']), ('value', 'invented')):
            bad = deepcopy(response); bad['decisions'][0][field] = value
            with self.assertRaises(ValueError): validate_review(chunk, bad)

    def test_unresolved_claim_cannot_be_promoted(self):
        chunk, response = self.fixture(); response['decisions'][0]['action'] = 'unresolved'
        with self.assertRaises(ValueError): validate_review(chunk, response)
        response['decisions'][0]['use_scope'] = 'research_only'
        result = validate_review(chunk, response)
        self.assertIn('independent_fact', result['decisions'][0]['approval'])

    def test_recovery_discards_echo_but_quarantines_implicit_repair(self):
        chunk, response = self.fixture()
        entry = chunk['payload']['entries'][0]
        decision = response['decisions'][0]
        decision.update({f: entry['claim'][f] for f in ('dimension', 'value', 'basis')})
        original_response = deepcopy(response)
        result = recover_review(chunk, response)
        self.assertEqual(response, original_response)
        self.assertEqual(result['response']['decisions'][0]['action'], 'supported')
        self.assertEqual(result['recovery_events'][0]['disposition'], 'discarded_exact_echo')
        decision['value'] = 'An unrequested rewrite'
        result = recover_review(chunk, response)
        recovered = result['response']['decisions'][0]
        self.assertEqual((recovered['action'], recovered['use_scope']), ('unresolved', 'research_only'))
        self.assertIsNone(recovered['value'])
        self.assertEqual(result['recovery_events'][0]['suggested_fields']['value'], decision['value'])

    def test_recovery_quarantines_bad_evidence_or_promotion_and_rejects_duplicate_coverage(self):
        chunk, response = self.fixture()
        response['decisions'][0].update(action='unresolved', use_scope='research_only', dimension='price')
        self.assertEqual(recover_review(chunk, response)['response']['decisions'][0]['action'], 'unresolved')
        for mutate in ('evidence', 'duplicate', 'promotion'):
            bad = deepcopy(response)
            if mutate == 'evidence': bad['decisions'][0]['evidence_segment_ids'] = ['other:000001']
            if mutate == 'duplicate': bad['decisions'] *= 2
            if mutate == 'promotion': bad['decisions'][0]['use_scope'] = 'discovery_context'
            if mutate == 'duplicate':
                with self.assertRaises(ValueError): recover_review(chunk, bad)
            else:
                with self.assertRaises(ValueError): validate_review(chunk, bad)
                result = recover_review(chunk, bad)
                result['raw_response'] = bad
                self.assertEqual(result['recovery_events'][0]['disposition'], 'invalid_source_review')
                self.assertTrue(load_review_cache(chunk, result)['decisions'][0]['approval'].startswith('not_reviewed;'))

    def test_saved_candidate_is_recovered_with_zero_paid_calls_and_bound_replay(self):
        chunk, response = self.fixture()
        response['decisions'][0]['value'] = 'Do not apply me'
        prepared = {'claim_occurrences': len(response['decisions']), 'chunks': [chunk]}
        with TemporaryDirectory() as directory, patch('trippy.sources.semantic_review.request_with_deadline') as provider:
            root = Path(directory)
            candidate = {'chunk_sha256': chunk['id'], 'response': response}
            raw_path = root / (chunk['id']+'.candidate.json')
            raw_path.write_text(json.dumps(candidate))
            raw_bytes = raw_path.read_bytes()
            result = execute(prepared, {'TRIPPY_AI_BUDGET_AMOUNT': '15'}, root/'no-ledger', root, max_calls=0)
            self.assertTrue(result['complete'])
            self.assertEqual(result['saved_candidates_recovered'], 1)
            self.assertEqual(result['new_validated_calls_this_execution'], 0)
            self.assertEqual(raw_path.read_bytes(), raw_bytes)
            self.assertTrue(execute(prepared, {'TRIPPY_AI_BUDGET_AMOUNT': '15'}, root/'no-ledger', root, max_calls=0)['complete'])
            provider.assert_not_called()
            cache = json.loads((root/(chunk['id']+'.json')).read_text())
            cache['response']['decisions'][0]['action'] = 'supported'
            with self.assertRaises(ValueError): load_review_cache(chunk, cache)

    def test_candidate_request_mismatch_stops_without_dispatch(self):
        chunk, response = self.fixture()
        with TemporaryDirectory() as directory, patch('trippy.sources.semantic_review.request_with_deadline') as provider:
            root = Path(directory)
            (root/(chunk['id']+'.candidate.json')).write_text(json.dumps({'chunk_sha256': 'wrong', 'response': response}))
            result = execute({'claim_occurrences': len(response['decisions']), 'chunks': [chunk]},
                             {'TRIPPY_AI_BUDGET_AMOUNT': '15'}, root/'no-ledger', root)
            self.assertFalse(result['complete'])
            self.assertEqual(result['failures'][0]['reason'], 'Saved candidate request differs')
            provider.assert_not_called()

    def test_provider_schema_forbids_implicit_repairs_and_unresolved_promotion(self):
        _, response = self.fixture()
        ProviderReview.model_validate(response)
        response['decisions'][0]['value'] = 'Implicit edit'
        with self.assertRaises(ValueError): ProviderReview.model_validate(response)
        response['decisions'][0].update(action='repair', dimension='price', basis='source_fact')
        ProviderReview.model_validate(response)
        response['decisions'][0].update(action='unresolved', dimension=None, value=None, basis=None)
        with self.assertRaises(ValueError): ProviderReview.model_validate(response)
        response['decisions'][0]['use_scope'] = 'research_only'
        ProviderReview.model_validate(response)

    def test_versioned_adoption_requires_identical_input_and_preserves_original(self):
        chunk, response = self.fixture()
        old = deepcopy(chunk); old['response_schema'] = {'legacy': True}
        old['id'] = fingerprint({k:v for k,v in old.items() if k != 'id'})
        with TemporaryDirectory() as directory:
            source = Path(directory)/'old'; source.mkdir(); target = Path(directory)/'new'
            manifest = {'chunks': [old]}; (source/'prepared.json').write_text(json.dumps(manifest))
            raw_path = source/(old['id']+'.candidate.json')
            raw_path.write_text(json.dumps({'chunk_sha256': old['id'], 'response': response}))
            original = raw_path.read_bytes()
            self.assertEqual(adopt_saved_candidates(source, target, {'chunks': [chunk]}), 1)
            self.assertEqual(adopt_saved_candidates(source, target, {'chunks': [chunk]}), 0)
            self.assertEqual(raw_path.read_bytes(), original)
            altered = deepcopy(chunk); altered['payload']['entries'][0]['name'] = 'Different subject'
            self.assertEqual(adopt_saved_candidates(source, Path(directory)/'different', {'chunks': [altered]}), 0)
            manifest['chunks'][0]['payload']['scope'] = 'tampered'
            (source/'prepared.json').write_text(json.dumps(manifest))
            with self.assertRaises(ValueError): adopt_saved_candidates(source, target, {'chunks': [chunk]})

    def test_keyed_schema_has_a_required_slot_for_every_claim(self):
        chunk, response = self.fixture()
        slots = chunk['response_schema']['properties']['decisions']
        self.assertEqual(set(slots['required']), {e['key'] for e in chunk['payload']['entries']})
        self.assertEqual(set(slots['properties']), set(slots['required']))
        self.assertFalse(slots['additionalProperties'])
        for definition in chunk['response_schema']['$defs'].values():
            self.assertNotIn('key', definition['properties'])
        keyed = {'decisions': {d['key']: {k:v for k,v in d.items() if k != 'key'} for d in response['decisions']}}
        self.assertEqual(validate_review(chunk, keyed), validate_review(chunk, response))
        keyed['decisions'][response['decisions'][0]['key']]['key'] = 'forged'
        with self.assertRaises(ValueError): response_as_list(keyed)

    def test_missing_claim_is_quarantined_and_does_not_stop_other_saved_batches(self):
        chunk, response = self.fixture()
        second = deepcopy(chunk)
        second['payload']['entries'][0]['key'] = 'another-claim'
        second['id'] = fingerprint({k:v for k,v in second.items() if k != 'id'})
        second_response = deepcopy(response); second_response['decisions'][0]['key'] = 'another-claim'
        recovered = recover_review(chunk, {'decisions': []})
        self.assertEqual(recovered['recovery_events'][0]['disposition'], 'missing_source_review')
        recovered['raw_response'] = {'decisions': []}
        self.assertTrue(load_review_cache(chunk, recovered)['decisions'][0]['approval'].startswith('not_reviewed;'))
        with TemporaryDirectory() as directory, patch('trippy.sources.semantic_review.request_with_deadline') as provider:
            root = Path(directory)
            for c, r in ((chunk, {'decisions': []}), (second, second_response)):
                (root/(c['id']+'.candidate.json')).write_text(json.dumps({'chunk_sha256':c['id'], 'response':r}))
            status = execute({'claim_occurrences': 2, 'chunks': [chunk, second]},
                {'TRIPPY_AI_BUDGET_AMOUNT':'15'}, root/'no-ledger', root, max_calls=0)
            self.assertEqual(status['claims_accounted'], 2)
            self.assertEqual(status['claims_received_source_review'], 1)
            self.assertEqual(status['state'], 'needs_targeted_source_review')
            self.assertFalse(status['complete'])
            self.assertEqual(status['omitted_claims_pending_source_review'], [chunk['payload']['entries'][0]['key']])
            provider.assert_not_called()

    def test_semantic_transport_allows_slow_response_without_sdk_retry(self):
        from unittest.mock import Mock
        connection = Mock()
        with patch('trippy.sources.luna.make_provider') as factory:
            factory.return_value.return_value = {'decisions': []}
            semantic_worker({'test':'config'}, 'ledger', {'test':'chunk'}, connection)
            factory.assert_called_once_with({'test':'config'}, 'ledger', max_output_tokens=8000, request_timeout=240)
            connection.send.assert_called_once_with(('ok', {'decisions': []}))
            connection.close.assert_called_once()


if __name__ == '__main__': unittest.main()
