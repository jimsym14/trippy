import io
import json
from contextlib import redirect_stdout
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from trippy.sources.download_audio import download_one, run_batch, validated_sources


def batch():
    return {"version":1,"sources":[{"external_id":x,"url":"https://youtu.be/"+x} for x in ("abcdefghijk","lmnopqrstuv")]}


class AudioDownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.folder=Path(self.temp.name)
        self.space=patch("trippy.sources.download_audio.shutil.disk_usage")
        self.disk=self.space.start();self.addCleanup(self.space.stop)
        self.disk.return_value.free=10_000_000_000

    def test_source_mismatch_does_not_start_batch(self):
        b=batch();b["sources"][0]["external_id"]="lmnopqrstuv"
        with self.assertRaises(ValueError):run_batch(b,self.folder/"batch")
        self.assertFalse((self.folder/"batch").exists())

    def test_disk_limit_checked_before_output_creation(self):
        self.disk.return_value.free=500_000_000
        with self.assertRaises(ValueError):run_batch(batch(),self.folder/"batch")
        self.assertFalse((self.folder/"batch").exists())

    def test_failed_source_retained_and_other_sources_continue(self):
        def fake(source,directory):
            if source["external_id"]=="abcdefghijk":raise RuntimeError("failed")
            return {"status":"downloaded_not_transcribed"}
        with redirect_stdout(io.StringIO()):r=run_batch(batch(),self.folder/"batch",downloader=fake)
        self.assertEqual(r["downloaded_count"],1)
        self.assertEqual(r["status"],"download_incomplete")
        self.assertEqual(r["content_rights"],"unverified")
        self.assertEqual(r["model_calls"],0)
        self.assertEqual(json.loads((self.folder/"batch/progress.json").read_text())["sources"][0]["status"],"download_failed")

    def test_existing_batch_preserved(self):
        out=self.folder/"batch";out.mkdir();(out/"keep").write_text("preserve")
        with self.assertRaises(FileExistsError):run_batch(batch(),out)
        self.assertEqual((out/"keep").read_text(),"preserve")

    def test_audio_validation_and_no_login_drm_or_geo_bypass(self):
        source=validated_sources(batch())[0]
        captured={}
        class Fake:
            def __init__(self,options):captured.update(options)
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def extract_info(self,url,download):
                p=self_path/"abcdefghijk.m4a";p.write_bytes(b"synthetic audio")
                return {"id":"abcdefghijk","requested_downloads":[{"filepath":str(p),"vcodec":"none"}],"duration":1}
        self_path=self.folder
        result=download_one(source,self.folder,factory=Fake)
        self.assertEqual(result["status"],"downloaded_not_transcribed")
        self.assertFalse(captured["geo_bypass"])
        self.assertNotIn("cookiesfrombrowser",captured)
        self.assertNotIn("cookiefile",captured)
        self.assertTrue(captured["match_filter"]({"has_drm":True}))
        self.assertTrue(captured["match_filter"]({"is_live":True}))


if __name__=="__main__":unittest.main()
