from uuid import uuid4
import json
from pathlib import Path
import tempfile
import unittest
from trippy.sources.social_ingest import SourceInput, PrivateSocialArchive, prepare_request, prepare_requests, validate_proposal, gaps


def source(**patch):
    value = dict(source_id=str(uuid4()), source_url='https://www.tiktok.com/@example/photo/12345678',
                 media_kind='slides', expected_slide_count=2,
                 evidence=[dict(id='slide1', origin='slide_ocr', text='Cafe Example — coffee and cakes', order=0),
                           dict(id='slide2', origin='slide_ocr', text='Museum Example — book ahead', order=1),
                           dict(id='caption', origin='post_caption', text='Two stops in Barcelona', order=-1)])
    value.update(patch)
    return SourceInput.model_validate(value)


def proposal():
    return dict(places=[dict(name='Cafe Example', short_description='Coffee and cakes', identity_uncertain=True,
                            citations=[dict(evidence_id='slide1', quote='Cafe Example — coffee and cakes')])],
                note_title='Barcelona notes', note_sections=[dict(title='Museum', body='The post recommends booking ahead.',
                        citations=[dict(evidence_id='slide2', quote='Museum Example — book ahead')])],
                reviewed_evidence_ids=['slide1','slide2','caption'], unresolved=['Branch not identified'])


class SocialIngestTests(unittest.TestCase):
    def test_every_slide_and_caption_preserved_in_request(self):
        document = source(); request = prepare_request(document)
        self.assertEqual({b['id']: b['text'] for b in request['input']['evidence']}, {b.id:b.text for b in document.evidence})
        self.assertEqual(gaps(document), [])
        self.assertTrue(validate_proposal(document, proposal()).places[0].identity_uncertain)

    def test_missing_slide_or_transcript_is_explicit(self):
        self.assertIn('slide_text_coverage_incomplete', gaps(source(expected_slide_count=3)))
        self.assertIn('video_transcript_or_captions_missing', gaps(source(media_kind='video', expected_slide_count=None)))
        with self.assertRaisesRegex(ValueError, 'retrieval'):
            prepare_request(source(media_kind='unknown', evidence=[], expected_slide_count=None))

    def test_omitted_evidence_and_fabricated_quotes_rejected(self):
        value = proposal(); value['reviewed_evidence_ids'].remove('slide2')
        with self.assertRaisesRegex(ValueError, 'accounted'):
            validate_proposal(source(), value)
        value = proposal(); value['places'][0]['citations'][0]['quote'] = 'Open every day at 8'
        with self.assertRaisesRegex(ValueError, 'exact'):
            validate_proposal(source(), value)

    def test_archive_idempotency_revisions_and_owner_boundary(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = PrivateSocialArchive(Path(folder)/'social.sqlite')
            owner = uuid4(); document = source()
            receipt = archive.ingest(owner, document); archive.ingest(owner, document)
            archive.save_proposal(owner, document, proposal())
            with self.assertRaisesRegex(ValueError, 'owned'):
                archive.save_proposal(uuid4(), document, proposal())
            updated = document.model_copy(deep=True); updated.evidence[0].text += '\nOriginal extra detail'
            archive.ingest(owner, updated)
            with archive.connect() as db:
                rows = db.execute('select payload from social_sources').fetchall()
            self.assertEqual(len(rows), 2)
            self.assertTrue(any(json.loads(row[0])['evidence'][0]['text'] == document.evidence[0].text for row in rows))
            self.assertEqual(receipt['canonical_facts_admitted'], 0)

    def test_chunking_keeps_every_character_and_parent_evidence_id(self):
        document = source()
        document.evidence[0].text = 'Long multilingual text Καφές. ' * 1400
        requests = prepare_requests(document, max_chars=1000)
        recovered = {block.id: '' for block in document.evidence}
        for request in requests:
            self.assertLessEqual(sum(len(block['text']) for block in request['input']['evidence']), 1000)
            for block in request['input']['evidence']:
                recovered[block['id']] += block['text']
        self.assertEqual(recovered, {block.id:block.text for block in document.evidence})

    def test_non_tiktok_url_and_oversize_request_fail_closed(self):
        with self.assertRaises(ValueError): source(source_url='https://tiktok.com.attacker.example/video/1')
        with self.assertRaisesRegex(ValueError, 'split'): prepare_request(source(), max_chars=10)


if __name__ == '__main__': unittest.main()
