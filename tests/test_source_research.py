import copy
from datetime import datetime, timezone
import json
from pathlib import Path
import tempfile
import unittest
from contextlib import redirect_stderr
import io
from unittest.mock import patch

from trippy.sources.planner import canonical_video, manual_sources, plan_queries
from trippy.sources.youtube import discover, reserve_search
from trippy.sources.transcripts import evidence_document, parse_transcript
from trippy.sources.cli import main


ROOT = Path(__file__).resolve().parents[1]


class SourceResearchTests(unittest.TestCase):
    def setUp(self):
        self.profile = json.loads((ROOT / "configs/source_research/barcelona.json").read_text())
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ledger = Path(self.temp.name) / "quota.sqlite"

    def test_breadth_and_languages_before_synonyms(self):
        plan = plan_queries(self.profile)
        self.assertEqual(plan["missing_topic_languages"], [])
        first_pass = plan["queries"][:len(self.profile["topics"])*2]
        self.assertEqual(len({(q["topic"],q["language_hint"]) for q in first_pass}), len(first_pass))
        self.assertEqual(plan["status"], "planned_not_executed")
        self.assertEqual(plan["paid_provider_calls"], 0)

    def test_cap_reports_uncovered_dimensions(self):
        self.profile["limits"]["max_queries"] = 1
        plan = plan_queries(self.profile)
        self.assertTrue(plan["missing_topic_languages"])
        self.assertEqual(len(plan["queries"]), 1)

    def test_controlled_language_and_gap_priority(self):
        self.profile["languages"] = ["en"]
        plan = plan_queries(self.profile, covered_topics=["overview"])
        self.assertNotEqual(plan["queries"][0]["topic"], "overview")
        self.assertEqual({q["language_hint"] for q in plan["queries"]}, {"en"})
        self.assertEqual(plan["profile_sha256"], plan_queries(copy.deepcopy(self.profile))["profile_sha256"])

    def test_unknown_template_or_language_is_not_silently_dropped(self):
        self.profile["topics"][0]["queries"]["en"] = ["{city} {user_secret}"]
        with self.assertRaises(ValueError): plan_queries(self.profile)
        self.profile["topics"][0]["queries"]["en"] = ["{city}"]
        self.profile["languages"] = ["es"]
        with self.assertRaises(ValueError): plan_queries(self.profile)

    def test_canonical_links_dedup_without_network(self):
        sources = manual_sources(["https://youtu.be/abcdefghijk?t=5", "https://www.youtube.com/watch?v=abcdefghijk&list=x"])
        self.assertEqual(len(sources), 1)
        self.assertEqual(sources[0]["scope"], "private")
        self.assertEqual(sources[0]["transcript_status"], "not_acquired")

    def test_external_or_ambiguous_hosts_rejected(self):
        for url in ["https://youtube.com.evil.test/watch?v=abcdefghijk", "http://youtu.be/abcdefghijk",
                    "https://user@youtube.com/watch?v=abcdefghijk", "https://youtube.com/watch?v=abcdefghijk&v=lmnopqrstuv",
                    "https://youtu.be/abcdefghijk/extra", "https://127.0.0.1/watch?v=abcdefghijk"]:
            with self.assertRaises(ValueError): canonical_video(url)

    def test_quota_is_durable_and_resets_in_pacific_time(self):
        now = datetime(2026,10,29,6,0,tzinfo=timezone.utc)
        reserve_search(self.ledger,"synthetic-key",daily_limit=1,now=now)
        with self.assertRaises(ValueError): reserve_search(self.ledger,"synthetic-key",daily_limit=1,now=now)
        reserve_search(self.ledger,"synthetic-key",daily_limit=1,now=datetime(2026,10,29,8,0,tzinfo=timezone.utc))

    def test_discovery_dedup_caps_and_unverified_language(self):
        self.profile["limits"]["max_queries"] = 2
        def fake(*args,**kwargs):return [{"id":{"videoId":"abcdefghijk"},"snippet":{"title":"Synthetic video"}}]
        result = discover(plan_queries(self.profile),"synthetic-key",self.ledger,requester=fake)
        self.assertEqual(len(result["sources"]), 1)
        self.assertEqual(len(result["sources"][0]["discovered_by_query_ids"]), 2)
        self.assertEqual(result["sources"][0]["language_status"], "unverified_search_hint_only")
        self.assertEqual(result["catalog_writes"],0)

    def test_failed_discovery_keeps_partial_status_and_reserved_quota(self):
        def fake(*args,**kwargs):raise ValueError("Synthetic quota failure")
        result = discover(plan_queries(self.profile),"synthetic-key",self.ledger,requester=fake)
        self.assertEqual(result["status"], "discovery_incomplete")
        self.assertTrue(result["not_executed_query_ids"])
        with self.assertRaises(ValueError):reserve_search(self.ledger,"synthetic-key",daily_limit=1)

    def test_timestamped_transcript_keeps_evidence_without_verification(self):
        text="WEBVTT\n\n00:01.000 --> 00:03.500\nA synthetic place recommendation.\n"
        result=evidence_document("https://youtu.be/abcdefghijk",text,"vtt",language="el",content_basis="creator_provided")
        self.assertEqual(result["segments"][0]["start_seconds"],1)
        self.assertEqual(result["status"],"evidence_imported_not_fact_checked")
        self.assertEqual(result["catalog_writes"],0)
        self.assertEqual(result["retrieval_time_status"],"unknown_unless_supplied_separately")

    def test_invalid_transcript_timing_and_content_basis_rejected(self):
        for text in ["1\n00:00:03,000 --> 00:00:01,000\nWrong order", "1\n00:61:00,000 --> 00:62:00,000\nInvalid minute", "not subtitles"]:
            with self.assertRaises(ValueError):parse_transcript(text,"srt")
        with self.assertRaises(ValueError):
            evidence_document("https://youtu.be/abcdefghijk","text","txt",language="en",content_basis="public_link_only")

    def test_plain_transcript_does_not_invent_timestamps(self):
        result=parse_transcript("Synthetic supplied notes","txt")
        self.assertIsNone(result[0]["start_seconds"])

    def test_missing_credentials_do_not_create_false_batch(self):
        output=Path(self.temp.name)/"not-created.json"
        with patch.dict("os.environ",{},clear=True), redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            main(["--profile",str(ROOT/"configs/source_research/barcelona.json"),"--output",str(output),
                  "--env-file",str(Path(self.temp.name)/"missing.env"),"--execute-youtube"])
        self.assertFalse(output.exists())

    def test_local_env_key_is_loaded_without_logging_secret(self):
        output=Path(self.temp.name)/"batch.json"
        env=Path(self.temp.name)/"local.env"
        env.write_text("YOUTUBE_API_KEY=synthetic-file-key\n")
        stream=io.StringIO()
        from contextlib import redirect_stdout
        def fake(plan,key,ledger):
            self.assertEqual(key,"synthetic-file-key")
            return {**plan,"status":"synthetic_discovery","sources":[]}
        with patch.dict("os.environ",{},clear=True),patch("trippy.sources.cli.discover",side_effect=fake),redirect_stdout(stream):
            main(["--profile",str(ROOT/"configs/source_research/barcelona.json"),"--output",str(output),
                  "--env-file",str(env),"--execute-youtube"])
        self.assertNotIn("synthetic-file-key",stream.getvalue()+output.read_text())

    def test_existing_batch_is_preserved(self):
        output=Path(self.temp.name)/"existing.json"
        output.write_text("preserve")
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            main(["--profile",str(ROOT/"configs/source_research/barcelona.json"),"--output",str(output)])
        self.assertEqual(output.read_text(),"preserve")


if __name__ == "__main__":
    unittest.main()
