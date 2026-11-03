import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from trippy.sources.asr import digest_file, transcribe_file


class LocalASRTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.folder=Path(self.temp.name);self.audio=self.folder/'audio.m4a';self.audio.write_bytes(b'synthetic audio')
        self.source={'external_id':'abcdefghijk','url':'https://youtu.be/abcdefghijk','provider':'youtube',
                     'input':str(self.audio),'sha256':digest_file(self.audio),'content_rights':'unverified'}

    def test_changed_audio_rejected_before_transcription(self):
        self.audio.write_bytes(b'changed')
        with patch('trippy.sources.asr.subprocess.run') as run,self.assertRaises(ValueError):
            transcribe_file(self.source,self.folder)
        run.assert_not_called()

    def test_source_identity_rejected_before_path_use(self):
        self.source['external_id']='../../private'
        with self.assertRaises(ValueError):transcribe_file(self.source,self.folder)

    def test_evidence_keeps_rights_and_accuracy_unverified(self):
        def fake(command,**kwargs):
            if '-of' in command:
                stem=Path(command[command.index('-of')+1])
                stem.with_suffix('.vtt').write_text('WEBVTT\n\n00:00.000 --> 00:03.000\nSynthetic recommendation\n')
                stem.with_suffix('.json').write_text(json.dumps({'result':{'language':'el'}}))
            self.assertIs(kwargs.get('stdin'),__import__('subprocess').DEVNULL)
        with patch('trippy.sources.asr.probe_duration',return_value=5),patch('trippy.sources.asr.shutil.disk_usage') as space,patch('trippy.sources.asr.subprocess.run',side_effect=fake):
            space.return_value.free=10_000_000_000
            result=transcribe_file(self.source,self.folder)
        evidence=json.loads(Path(result['evidence_file']).read_text())
        self.assertEqual(evidence['content_rights'],'unverified')
        self.assertEqual(evidence['status'],'transcribed_not_fact_checked')
        self.assertEqual(evidence['model_api_calls'],0)
        self.assertEqual(evidence['language'],'el')
        self.assertEqual(evidence['segments'][0]['end_seconds'],3)


if __name__=='__main__':unittest.main()
