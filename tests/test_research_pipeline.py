import copy
import json
import unittest
import tempfile
import importlib.util
import types
from pathlib import Path
from unittest.mock import Mock, patch

from research_pipeline import (
    CONTRACT_PATH, audit_result, build_scout_prompt, build_synthesis_prompt,
    canonical_category, prepare_result, trip_dates,
)


def fixture():
    document = json.loads(CONTRACT_PATH.read_text())
    for key, value in list(document.items()):
        if isinstance(value, list):
            document[key] = []
    document["overview"]["summary"] = "A proposed trip"
    document["map_overview"]["title"] = "Trip map"
    document["places"] = [
        {"id": "P1", "category": "museum", "name": "A", "coordinates": {"latitude": 41.4, "longitude": 2.1}, "source_ids": ["S1"]},
        {"id": "P2", "category": "museum", "name": "B", "coordinates": {"latitude": 41.3, "longitude": 2.2}, "source_ids": ["S1"]},
    ]
    document["sources"] = [{"id": "S1", "url": "https://example.org/official", "checked_at": "2026-10-28"}]
    document["transport_options"] = [{"id": "T1", "source_ids": ["S1"]}]
    document["ticket_options"] = [{"id": "K1", "source_ids": ["S1"]}]
    document["costs"]["per_person_estimate"] = {"min": 20, "max": 30}
    document["itinerary"]["days"] = [
        {"date": "2026-12-05", "day": 1, "stops": [{"place_id": "P2"}, {"place_id": "P1"}]},
        {"date": "2026-12-06", "day": 2, "stops": [{"place_id": "P1"}]},
    ]
    document["calendar_checks"] = [{"date": "2026-12-05"}, {"date": "2026-12-06"}]
    document["date_checks"] = [
        {"entity_id": "P2", "local_date": "2026-12-05"},
        {"entity_id": "P1", "local_date": "2026-12-05"},
        {"entity_id": "P1", "local_date": "2026-12-06"},
    ]
    return document


BRIEF = {"destination": "Barcelona", "date_range": {"arrival": "2026-12-05", "departure": "2026-12-06"}, "interests": ["Μουσεία"]}


class ResearchPipelineTests(unittest.TestCase):
    def test_bridge_reports_partial_results_without_automatic_paid_retries(self):
        sdk = types.ModuleType("openai")
        sdk.OpenAI = Mock()
        sdk.AzureOpenAI = Mock()
        spec = importlib.util.spec_from_file_location("bridge_test", Path(__file__).resolve().parents[1] / "bridge_server.py")
        bridge = importlib.util.module_from_spec(spec)
        with patch.dict("sys.modules", {"openai": sdk}), patch.object(Path, "exists", return_value=False):
            spec.loader.exec_module(bridge)
        sdk.OpenAI.return_value.conversations.create.return_value.id = "fixture"
        sdk.OpenAI.return_value.responses.create.return_value.output_text = "Fixture facts"
        document = fixture()
        for day in document["itinerary"]["days"]:
            day["stops"] = []
        sdk.AzureOpenAI.return_value.chat.completions.create.return_value.choices = [
            types.SimpleNamespace(message=types.SimpleNamespace(content=json.dumps(document)))
        ]
        with tempfile.TemporaryDirectory() as temporary, patch.object(bridge, "__file__", str(Path(temporary) / "bridge_server.py")):
            bridge.run_pipeline(BRIEF)
        self.assertEqual(bridge.state.current_step, "completed")
        self.assertEqual(bridge.state.latest_result["quality_report"]["status"], "partial")
        self.assertIn("κενά", bridge.state.step_message)
        sdk.OpenAI.return_value.responses.create.assert_called_once()
        sdk.AzureOpenAI.return_value.chat.completions.create.assert_called_once()

    def test_every_populated_day_has_a_map_with_exact_stop_order(self):
        original = fixture()
        snapshot = copy.deepcopy(original)
        result = prepare_result(original, BRIEF)
        self.assertEqual(original, snapshot, "Do not mutate the original response")
        maps = {row["id"]: row for row in result["map_views"]}
        for day in result["itinerary"]["days"]:
            self.assertEqual(maps[day["map_view_id"]]["place_ids"], [stop["place_id"] for stop in day["stops"]])
        self.assertEqual(result["quality_report"]["status"], "ready")

    def test_day_segments_have_maps_without_reordering_or_duplicate_places(self):
        document = fixture()
        document["itinerary"]["days"][0]["stops"][0]["period"] = "morning"
        document["itinerary"]["days"][0]["stops"][1]["period"] = "evening"
        result = prepare_result(document, BRIEF)
        day = result["itinerary"]["days"][0]
        maps = {row["id"]: row for row in result["map_views"]}
        self.assertEqual(maps[day["map_view_id"]]["place_ids"], ["P2", "P1"])
        self.assertEqual(maps["map-day-2026-12-05-morning"]["place_ids"], ["P2"])
        self.assertEqual(maps["map-day-2026-12-05-evening"]["place_ids"], ["P1"])
        self.assertEqual(len(day["segment_map_ids"]), 2)

    def test_invalid_model_map_projection_is_rebuilt_without_losing_research(self):
        document = fixture()
        document["map_views"] = [{"id": "duplicate"}, {"id": "duplicate"}]
        result = prepare_result(document, BRIEF)
        self.assertEqual(result["quality_report"]["status"], "ready")
        self.assertEqual(result["places"], document["places"])
        self.assertEqual(len(result["map_views"]), 3)

    def test_missing_coordinates_stay_unknown_and_maps_are_partial(self):
        document = fixture()
        document["places"][0]["coordinates"] = {"latitude": None, "longitude": None}
        result = prepare_result(document, BRIEF)
        self.assertEqual(result["quality_report"]["status"], "partial")
        self.assertIsNone(result["places"][0]["coordinates"]["latitude"])
        self.assertEqual(next(row for row in result["map_views"] if row["date"] == "2026-12-05")["status"], "partial")

    def test_empty_days_cannot_pass_coverage_check(self):
        document = fixture()
        for day in document["itinerary"]["days"]:
            day["stops"] = []
        result = prepare_result(document, BRIEF)
        self.assertEqual(result["quality_report"]["metrics"]["populated_days"], 0)
        self.assertEqual(result["quality_report"]["status"], "partial")
        self.assertTrue(any(row["id"] == "coverage-audit" for row in result["warnings"]))

    def test_duplicate_ids_and_unresolved_references_fail(self):
        for mutation in ("duplicate", "reference", "wrong_type", "bad_id"):
            document = fixture()
            if mutation == "duplicate":
                document["places"][1]["id"] = "P1"
            elif mutation == "reference":
                document["itinerary"]["days"][0]["stops"][0]["place_id"] = "MISSING"
            elif mutation == "bad_id":
                document["sources"][0]["id"] = {}
            else:
                document["itinerary"]["days"][0]["stops"] = None
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                prepare_result(document, BRIEF)

    def test_nonfinite_coordinates_cannot_be_published_as_json(self):
        document = fixture()
        document["places"][0]["coordinates"]["latitude"] = float("nan")
        with self.assertRaises(ValueError):
            prepare_result(document, BRIEF)

    def test_developer_preview_never_initializes_paid_clients(self):
        import run_research
        with tempfile.TemporaryDirectory() as temporary:
            brief_path = Path(temporary) / "brief.json"
            brief_path.write_text(json.dumps(BRIEF))
            output = Path(temporary) / "plan"
            with patch("sys.argv", ["run_research.py", "--brief", str(brief_path), "--output-dir", str(output)]), \
                 patch.object(run_research, "get_clients", side_effect=AssertionError("Preview called paid client")) as clients:
                run_research.main()
            clients.assert_not_called()
            self.assertTrue((output / "scout-prompt.txt").exists())
            self.assertTrue((output / "synthesis-prompt.txt").exists())

    def test_patch_is_not_treated_as_a_complete_document(self):
        self.assertEqual(audit_result({"schema_version": "trippy-research-patch-v2"}, BRIEF)["status"], "invalid")

    def test_dates_are_inclusive_and_unknown_dates_are_not_invented(self):
        self.assertEqual(len(trip_dates(BRIEF)), 2)
        self.assertEqual(trip_dates({"date_range": {"dates_unknown": True}}), [])
        self.assertEqual(trip_dates({}), [])
        with self.assertRaises(ValueError):
            trip_dates({"date_range": {"arrival": "2026-12-06", "departure": "2026-12-05"}})

    def test_prompts_honor_categories_and_distinguish_plans_from_live_slots(self):
        self.assertEqual(canonical_category("Εστιατόριο / tapas bar"), "food")
        self.assertEqual(canonical_category("Μουσεία"), "museum")
        scout = build_scout_prompt({**BRIEF, "dietary_needs": ["Χωρίς ξηρούς καρπούς"]})
        self.assertIn("Χωρίς ξηρούς καρπούς", scout)
        self.assertIn("museum", scout)
        self.assertIn("συντεταγμένες", scout)
        self.assertIn("status=proposed", build_synthesis_prompt())


if __name__ == "__main__":
    unittest.main()
