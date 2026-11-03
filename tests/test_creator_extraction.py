import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from trippy.sources.creators import city_relevant, discover_creators, load_creators
from trippy.sources.extraction import aggregate, chunk_evidence, execute_chunks, quality_flags, validate_result
from trippy.sources.asr import MODEL_SHA256, reusable_evidence, parse_whisper_vtt, emit_evidence, source_language
from hashlib import sha256
from decimal import Decimal
from trippy.sources.luna import BudgetError, make_provider, reserve_cost


class ExtractionTests(unittest.TestCase):
    def evidence(self):
        return {'source': {'provider': 'youtube', 'external_id': 'abcdefghijk',
            'url': 'https://www.youtube.com/watch?v=abcdefghijk'}, 'language': 'en',
            'segments': [{'text': 'Cafe Example serves excellent coffee in Barcelona. ' * 4,
                          'start_seconds': 0., 'end_seconds': 10.}],
            'audio_sha256': 'audio', 'model_sha256': MODEL_SHA256}

    def fixture(self):
        chunks, _ = chunk_evidence(self.evidence(), {'channel_id': 'publisher'})
        citation = {'segment_id': 'abcdefghijk:000000', 'start_seconds': 0., 'end_seconds': 10.,
                    'quote': 'Cafe Example serves excellent coffee in Barcelona.'}
        raw = {'mentions': [{'name': 'Cafe Example', 'aliases': [], 'kind': 'venue',
            'categories': ['coffee'], 'stance': 'recommended', 'identity_uncertain': False,
            'identity_uncertainty_reason': None, 'experience': 'unknown',
            'branch': None, 'claims': [{'dimension': 'vibe', 'value': 'excellent coffee',
                'basis': 'creator_opinion', 'observed_at': None, 'citations': [citation]}],
            'rating': None, 'citations': [citation]}]}
        return chunks[0], raw

    def test_forged_quotes_times_names_categories_rejected(self):
        chunk, raw = self.fixture()
        for mutation in ('quote', 'time', 'name', 'category', 'field'):
            bad = copy.deepcopy(raw)
            if mutation == 'quote': bad['mentions'][0]['citations'][0]['quote'] = 'invented'
            if mutation == 'time': bad['mentions'][0]['citations'][0]['end_seconds'] = 9.
            if mutation == 'name': bad['mentions'][0]['name'] = 'Invented venue'
            if mutation == 'category': bad['mentions'][0]['categories'] = ['imaginary']
            if mutation == 'field': bad['mentions'][0]['execute'] = 'delete database'
            with self.subTest(mutation=mutation), self.assertRaises(ValueError): validate_result(chunk, bad)

    def test_overlap_and_branch_dedup(self):
        chunk, raw = self.fixture()
        second = copy.deepcopy(raw)
        second['mentions'][0]['claims'].append({**second['mentions'][0]['claims'][0], 'dimension': 'cuisine'})
        third = copy.deepcopy(raw); third['mentions'][0]['branch'] = 'different address'
        result = aggregate([(chunk, raw), (chunk, raw), (chunk, second), (chunk, third)])
        self.assertEqual(len(result['drafts']), 2)
        self.assertEqual(len(result['drafts'][0]['claims']), 2)
        self.assertTrue(all(g['independent_publisher_count'] == 1 for g in result['review_queue']))
        self.assertEqual(result['catalog_writes'], 0)

    def test_case_variant_overlap_preserves_identity_uncertainty(self):
        chunk, raw = self.fixture()
        variant = copy.deepcopy(raw)
        mention = variant['mentions'][0]
        mention.update(name='cafe Example', identity_uncertain=True,
                       identity_uncertainty_reason='ASR spelling needs identity review')
        for occurrences in ([(chunk, raw), (chunk, variant)],
                            [(chunk, variant), (chunk, raw)]):
            result = aggregate(occurrences)
            self.assertEqual(len(result['drafts']), 1)
            draft = result['drafts'][0]
            self.assertTrue(draft['identity_uncertain'])
            self.assertEqual(draft['identity_uncertainty_reason'],
                             'ASR spelling needs identity review')
            self.assertEqual({draft['name'], *draft['aliases']},
                             {'Cafe Example', 'cafe Example'})

    def test_different_experiences_are_not_silently_deduplicated(self):
        chunk, raw = self.fixture()
        variant = copy.deepcopy(raw)
        variant['mentions'][0]['experience'] = 'first_hand_visit'
        self.assertEqual(len(aggregate([(chunk, raw), (chunk, variant)])['drafts']), 2)

    def test_music_and_repetition_rejected(self):
        e = self.evidence(); e['segments'][0]['text'] = '(upbeat music)'
        self.assertTrue(quality_flags(e))
        self.assertFalse(chunk_evidence(e)[0])
        e = self.evidence(); e['segments'] *= 30
        self.assertIn('excessive_repetition', quality_flags(e))

    def test_creator_hint_does_not_override_video_language(self):
        self.assertEqual(source_language({'language_hint':'el'}),'auto')
        self.assertEqual(source_language({'language_hint':'el','declared_audio_language':'en-GB'}),'en')
        self.assertEqual(source_language({'declared_audio_language':'en'},'el'),'el')

    def test_zero_duration_asr_cues_audited_without_fabricated_time(self):
        text='WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nCafe Example\n\n00:00:03.000 --> 00:00:03.000\nnoise'
        segments,excluded=parse_whisper_vtt(text)
        self.assertEqual(len(segments),1);self.assertEqual(segments[0]['end_seconds'],2.)
        self.assertEqual(len(excluded),1)
        with self.assertRaises(ValueError):parse_whisper_vtt(text.replace('00:00:02.000','00:00:00.000'))

    def test_outside_audio_cue_excluded_with_raw_audit(self):
        with tempfile.TemporaryDirectory() as directory:
            stem=Path(directory)/'abcdefghijk'
            stem.with_suffix('.vtt').write_text('WEBVTT\n\n00:00:00.000 --> 00:00:03.000\nCafe Example\n\n00:00:04.000 --> 00:00:10.000\ninvalid tail')
            stem.with_suffix('.json').write_text(json.dumps({'result':{'language':'en'}}))
            source={**self.evidence()['source'],'sha256':'audio'}
            result=emit_evidence(source,stem,5.,model_sha256=MODEL_SHA256,language='en')
            evidence=json.loads(Path(result['evidence_file']).read_text())
            self.assertEqual(evidence['segments'][0]['end_seconds'],3.)
            self.assertEqual(len(evidence['segments']),1)
            self.assertEqual(evidence['excluded_cues'][0]['original_segment']['end_seconds'],10.)
            self.assertEqual(evidence['coverage_status'],'partial_invalid_cues_excluded')

    def test_luna_provider_only_uses_configured_deployment(self):
        from types import SimpleNamespace
        from trippy.sources.extraction import Extraction
        chunk,raw=self.fixture();calls=[];client_options=[]
        def parse(**kwargs):
            calls.append(kwargs)
            message=SimpleNamespace(refusal=None,content=json.dumps(raw))
            return SimpleNamespace(choices=[SimpleNamespace(finish_reason='stop',message=message)])
        client=SimpleNamespace(chat=SimpleNamespace(completions=SimpleNamespace(create=parse)))
        values={'TRIPPY_ALLOW_PAID_RESEARCH':'true','TRIPPY_AI_BUDGET_AMOUNT':'1',
            'TRIPPY_AI_BUDGET_CURRENCY':'USD','TRIPPY_LUNA_INPUT_PER_MILLION':'1',
            'TRIPPY_LUNA_OUTPUT_PER_MILLION':'1','AZURE_OPENAI_API_KEY':'test-only',
            'AZURE_DEPLOYMENT_LUNA':'configured-luna','AZURE_OPENAI_ENDPOINT':'https://example.openai.azure.com/'}
        with tempfile.TemporaryDirectory() as directory:
            def factory(**options):
                client_options.append(options)
                return client
            provider=make_provider(values,Path(directory)/'budget.sqlite',client_factory=factory,request_timeout=240)
            self.assertEqual(provider(chunk),raw)
        self.assertEqual(calls[0]['model'],'configured-luna')
        self.assertEqual(len(calls),1)
        self.assertEqual(client_options[0]['timeout'],240)
        self.assertEqual(client_options[0]['max_retries'],0)

    def test_provider_timeout_is_finite_bounded_and_numeric(self):
        for timeout in (0, -1, 601, float('inf'), float('nan'), True, '240'):
            with self.assertRaisesRegex(BudgetError, 'Provider timeout'):
                make_provider({}, 'unused', request_timeout=timeout)

    def test_explicit_rating_only(self):
        chunk, raw = self.fixture()
        raw['mentions'][0]['rating'] = {'value': 4.5, 'scale': 5, 'platform': 'Google',
            'citations': raw['mentions'][0]['citations']}
        with self.assertRaises(ValueError): validate_result(chunk, raw)
        quote = 'Cafe Example has Google 4.5/5 stars.'
        chunk['payload']['segments'][0]['text'] = quote
        for cite in raw['mentions'][0]['citations']: cite['quote'] = quote
        self.assertEqual(validate_result(chunk, raw)['mentions'][0]['rating']['value'], 4.5)

    def test_chunking_preserves_citations_and_bounds(self):
        e = self.evidence(); e['segments'] = [
            {'text': 'Cafe Example. ' * 40, 'start_seconds': float(i), 'end_seconds': float(i+1)} for i in range(10)]
        chunks, flags = chunk_evidence(e, max_chars=1000, overlap=2)
        self.assertFalse(flags)
        self.assertGreater(len(chunks), 1)
        self.assertEqual({s['segment_id'] for c in chunks for s in c['payload']['segments']},
                         {f'abcdefghijk:{i:06d}' for i in range(10)})

    def test_cache_retries_and_partial_failure(self):
        chunk, raw = self.fixture(); calls = []
        def provider(c):
            calls.append(c['id'])
            if len(calls) == 1: raise ValueError('refused')
            return raw
        with tempfile.TemporaryDirectory() as directory:
            results, errors = execute_chunks([chunk], provider, directory)
            self.assertEqual(len(calls), 2); self.assertFalse(errors)
            execute_chunks([chunk], provider, directory)
            self.assertEqual(len(calls), 2)
            results, errors = execute_chunks([{**chunk, 'id': 'another'}], lambda _: {}, directory)
            self.assertFalse(results); self.assertEqual(len(errors), 1)

    def test_reuse_requires_audio_and_model_identity_and_quality(self):
        e = self.evidence()
        source = {'external_id': 'abcdefghijk', 'sha256': 'audio'}
        with tempfile.TemporaryDirectory() as directory:
            e['segments'][0]['text']=e['segments'][0]['text'].strip()
            vtt='WEBVTT\n\n00:00:00.000 --> 00:00:10.000\n'+e['segments'][0]['text']+'\n';e['transcript_sha256']=sha256(vtt.encode()).hexdigest()
            Path(directory, 'abcdefghijk.vtt').write_text(vtt)
            Path(directory, 'abcdefghijk.evidence.json').write_text(json.dumps(e))
            self.assertTrue(reusable_evidence(source, [directory]))
            self.assertIsNone(reusable_evidence({**source, 'sha256': 'changed'}, [directory]))
            e['segments'][0]['text']='invented speech'
            Path(directory, 'abcdefghijk.evidence.json').write_text(json.dumps(e))
            self.assertIsNone(reusable_evidence(source,[directory]))
            Path(directory, 'abcdefghijk.vtt').write_text('tampered')
            self.assertIsNone(reusable_evidence(source, [directory]))

    def test_paid_gate_and_durable_cost_cap(self):
        with self.assertRaises(BudgetError): make_provider({}, 'unused')
        with tempfile.TemporaryDirectory() as directory:
            ledger=Path(directory)/'budget.sqlite'
            reserve_cost(ledger,Decimal('.4'),Decimal('1'),'USD')
            reserve_cost(ledger,Decimal('.4'),Decimal('1'),'USD')
            with self.assertRaises(BudgetError): reserve_cost(ledger,Decimal('.4'),Decimal('1'),'USD')
            with self.assertRaises(BudgetError): reserve_cost(ledger,Decimal('.1'),Decimal('1'),'EUR')

    def test_overture_full_inventory_read_only(self):
        from trippy.sources.extraction import identity_candidates
        catalog=Path(__file__).resolve().parents[1]/'.local/catalog.sqlite'
        if not catalog.exists(): self.skipTest('local catalog not installed')
        before=catalog.stat().st_mtime_ns
        chunk,raw=self.fixture()
        mention=raw['mentions'][0];mention['name']='Sagrada'
        candidates=identity_candidates(mention,catalog)
        self.assertTrue(candidates)
        self.assertTrue(all(c['decision']=='identity_candidate_needs_review' for c in candidates))
        self.assertEqual(before,catalog.stat().st_mtime_ns)
        mention['name']='Σαγράδα Φαμίλια'
        self.assertTrue(identity_candidates(mention,catalog))


class CreatorTests(unittest.TestCase):
    def test_defaults_and_wrong_city(self):
        path = Path(__file__).resolve().parents[1] / 'configs/source_research/creators.json'
        self.assertEqual(len(load_creators(path, ['el', 'en'])), 8)
        self.assertEqual(len(load_creators(path, ['el'])), 3)
        self.assertFalse(city_relevant('Madrid Travel Guide', ['Barcelona', 'Βαρκελώνη']))
        self.assertTrue(city_relevant('Εικόνες Βαρκελώνη - Μέρος 2ο', ['Barcelona', 'Βαρκελώνη']))

    def test_parts_channel_identity_and_creator_fairness(self):
        creators = [{'id': str(i), 'name': str(i), 'language': 'el', 'channel_id': 'channel'+str(i)} for i in range(2)]
        def requester(resource, params, key):
            if resource == 'search':
                return {'items': [{'id': {'videoId': video}, 'snippet': {'channelId': params['channelId'],
                    'title': f'Barcelona Part {n}'}} for n, video in enumerate(['abcdefghijk', 'lmnopqrstuv'])]}
            return {'items': [{'id': video, 'snippet': {'channelId': creators[0]['channel_id']},
                'statistics': {'viewCount': '100'}, 'contentDetails': {'duration': 'PT40M'},
                'status': {'privacyStatus': 'public'}} for video in params['id'].split(',')]}
        with patch('trippy.sources.creators.reserve_search'):
            result = discover_creators(creators[:1], ['Barcelona'], 'key', 'ledger', requester=requester)
        self.assertEqual(len(result['sources']), 2)
        self.assertTrue(all(s['channel_id'] == 'channel0' for s in result['sources']))


if __name__ == '__main__': unittest.main()
