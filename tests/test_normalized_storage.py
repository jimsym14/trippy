import argparse
import copy
import io
import json
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

from alembic import command
from alembic.config import Config
from sqlalchemy import insert, inspect, select, text
from sqlalchemy.exc import IntegrityError

from trippy.data.database import make_engine, sqlite_url
from trippy.data import schema_v3 as s
from trippy.data.imports import ImportConflict, import_trip, load_trip
from trippy.legacy import export_research_v1, merge_legacy_patch, normalize_legacy_trip


ROOT = Path(__file__).resolve().parents[1]
OWNER_A = "00000000-0000-4000-8000-000000000001"
OWNER_B = "00000000-0000-4000-8000-000000000002"


def legacy_fixture():
    return {
        "id": "legacy-library-trip",
        "brief": {"destination": "Barcelona", "startDate": "2026-12-05", "endDate": "2026-12-06",
                  "interests": ["Φαγητό", "Καφές", "Αξιοθέατα"], "budget": None},
        "research": {
            "schema_version": "trippy-research-v1", "trip_context": {"destination": "Barcelona"},
            "places": [
                {"id": "P1", "name": "First museum", "category": "museum", "tags": ["culture"], "source_ids": ["S1"],
                 "coordinates": {"latitude": None, "longitude": None, "precision_note": "unknown source precision"}, "custom_field": "keep me",
                 "rating": {"value": 4.6, "scale": 5, "platform": "Synthetic", "review_count": 10}},
                {"id": "P2", "name": "Second museum", "category": "museum", "tags": [], "source_ids": ["S1"]},
            ],
            "sources": [{"id": "S1", "url": "https://example.org/source", "publisher": "Synthetic", "checked_at": "2026-10-20"}],
            "itinerary": {"planner_note": "preserve itinerary metadata", "days": [{"date": "2026-12-05", "theme": "Culture", "stops": [
                {"place_id": "P1", "time": "09:00", "activity": "Museum visit"},
                {"place_id": "P2", "time": "14:00", "activity": "Other visit"},
            ]}]},
            "transport_options": [{"id": "T1", "name": "Metro", "source_ids": ["S1"]}],
            "custom_module": {"value": "preserve unsupported module"},
        },
        "scheduleOrderByDate": {"2026-12-05": ["place|P2", "stop|2026-12-05|0"]},
        "scheduleEditsByItemID": {"place|P2": {"time": "after lunch", "costPerPerson": "12.50"}},
        "reactionsByItemID": {"place|P1": "like", "place|P2": "maybe"},
        "checklistDoneIDs": ["K1"],
        "budgetEntries": [{"id": "B1", "title": "Lunch", "amount": "12.50", "basis": "person"}],
        "mapCoordinatesByPlaceID": {"P2": {"latitude": 41.3, "longitude": 2.2, "source": "user", "matchedAt": 0}},
        "future_app_field": {"must": "survive"},
    }


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.config = Config(str(ROOT / "alembic.ini"))
        self.url = sqlite_url(Path(self.temporary.name) / "catalog.sqlite")
        self.config.set_main_option("sqlalchemy.url", self.url)
        command.upgrade(self.config, "head")
        self.engine = make_engine(self.url)

    def tearDown(self):
        self.engine.dispose()
        self.temporary.cleanup()

    def seed_owners(self, connection):
        connection.execute(insert(s.app_users), [{"id": OWNER_A}, {"id": OWNER_B}])
        self.trip_a, self.trip_b, self.place_a, self.place_b = [str(uuid4()) for _ in range(4)]
        connection.execute(insert(s.trips), [
            {"id": self.trip_a, "owner_id": OWNER_A, "destination": "A"},
            {"id": self.trip_b, "owner_id": OWNER_B, "destination": "B"},
        ])
        connection.execute(insert(s.user_places), [
            {"id": self.place_a, "owner_id": OWNER_A, "name": "A"},
            {"id": self.place_b, "owner_id": OWNER_B, "name": "B"},
        ])

    def test_alembic_upgrade_is_repeatable_and_has_no_schema_drift(self):
        from alembic.autogenerate import compare_metadata
        from alembic.migration import MigrationContext
        command.upgrade(self.config, "head")
        with self.engine.connect() as connection:
            self.assertEqual(connection.execute(text("SELECT version_num FROM alembic_version")).scalar_one(), "0003")
            self.assertEqual(set(inspect(connection).get_table_names()) - {"alembic_version"}, set(s.metadata.tables))
            self.assertEqual(compare_metadata(MigrationContext.configure(connection), s.metadata), [])

    def test_cross_owner_trip_and_place_references_are_rejected(self):
        with self.engine.begin() as connection:
            self.seed_owners(connection)
        with self.assertRaises(IntegrityError), self.engine.begin() as connection:
            connection.execute(insert(s.trip_decisions), {"id": str(uuid4()), "owner_id": OWNER_B,
                "trip_id": self.trip_a, "kind": "activity", "purpose": "Visit", "context": {}})
        with self.assertRaises(IntegrityError), self.engine.begin() as connection:
            connection.execute(insert(s.visit_history), {"id": str(uuid4()), "owner_id": OWNER_A, "user_place_id": self.place_b})

    def test_source_scope_cannot_be_relabelled_shared_or_another_owner(self):
        with self.engine.begin() as connection:
            self.seed_owners(connection)
            self.policy, self.source, self.entity = [str(uuid4()) for _ in range(3)]
            connection.execute(insert(s.source_policies), {"id": self.policy, "provider": "test", "policy_version": "1", "allowed_fields": []})
            connection.execute(insert(s.source_records), {"id": self.source, "owner_id": OWNER_B, "scope_key": OWNER_B,
                "policy_id": self.policy, "url": "https://example.org/private"})
            connection.execute(insert(s.entities), {"id": self.entity, "kind": "place", "name": "Public", "category": "museum"})
        for owner, scope, target in ((OWNER_A, OWNER_A, {"user_place_id": self.place_a}),
                                     (None, "shared", {"entity_id": self.entity})):
            with self.subTest(scope=scope), self.assertRaises(IntegrityError), self.engine.begin() as connection:
                connection.execute(insert(s.observations), {"id": str(uuid4()), "owner_id": owner, "scope_key": scope,
                    "source_id": self.source, "field_key": "rating", **target})

    def test_candidate_must_belong_to_its_selected_decision(self):
        trip = normalize_legacy_trip(legacy_fixture(), owner_id=OWNER_A)
        with self.engine.begin() as connection:
            import_trip(connection, trip)
        first, second = trip.decisions[:2]
        with self.assertRaises(IntegrityError), self.engine.begin() as connection:
            connection.execute(s.decision_selections.update().where(s.decision_selections.c.decision_id == str(first.id)).values(
                selected_candidate_id=str(second.candidates[0].id)))

    def test_activity_day_must_be_in_the_same_trip(self):
        trip = normalize_legacy_trip(legacy_fixture(), owner_id=OWNER_A)
        with self.engine.begin() as connection:
            import_trip(connection, trip)
            other_trip, other_day = str(uuid4()), str(uuid4())
            connection.execute(insert(s.trips), {"id": other_trip, "owner_id": OWNER_A, "destination": "Elsewhere"})
            connection.execute(insert(s.trip_days), {"id": other_day, "owner_id": OWNER_A, "trip_id": other_trip, "day_number": 1})
        with self.assertRaises(IntegrityError), self.engine.begin() as connection:
            connection.execute(s.activity_slots.update().where(s.activity_slots.c.decision_id == str(trip.decisions[0].id)).values(day_id=other_day))

    def test_five_star_rating_and_money_constraints(self):
        trip = normalize_legacy_trip(legacy_fixture(), owner_id=OWNER_A)
        with self.engine.begin() as connection:
            import_trip(connection, trip)
            snapshot_id = connection.execute(select(s.rating_snapshots.c.id)).scalar_one()
        for changes in ({"rating_scale": 10}, {"rating_value": 5.1}, {"review_count": -1}):
            with self.subTest(changes=changes), self.assertRaises(IntegrityError), self.engine.begin() as connection:
                connection.execute(s.rating_snapshots.update().where(s.rating_snapshots.c.id == snapshot_id).values(**changes))
        with self.assertRaises(IntegrityError), self.engine.begin() as connection:
            connection.execute(insert(s.cost_lines), {"id": str(uuid4()), "owner_id": OWNER_A, "trip_id": str(trip.id),
                "title": "Invalid cost", "amount": -1, "basis": "person", "origin": "user"})

    def test_legacy_migration_roundtrip_preserves_user_data_and_unknowns(self):
        original = legacy_fixture()
        snapshot = copy.deepcopy(original)
        bundle = normalize_legacy_trip(original, owner_id=OWNER_A)
        with self.engine.begin() as connection:
            self.assertEqual(import_trip(connection, bundle)["status"], "imported")
            loaded = load_trip(connection, trip_id=bundle.id, owner_id=OWNER_A)
            self.assertIsNone(load_trip(connection, trip_id=bundle.id, owner_id=OWNER_B))
        self.assertEqual(original, snapshot)
        self.assertEqual(loaded.app_owned_state, bundle.app_owned_state)
        self.assertEqual(loaded.id_map, bundle.id_map)
        self.assertEqual(loaded.legacy_modules, bundle.legacy_modules)
        self.assertEqual(loaded.places[0].legacy_fields, bundle.places[0].legacy_fields)
        self.assertEqual(loaded.claims, bundle.claims)
        projected = export_research_v1(loaded)
        self.assertEqual([r["place_id"] for r in projected["itinerary"]["days"][0]["stops"]], ["P2", "P1"])
        self.assertEqual(projected["itinerary"]["days"][0]["stops"][0]["time"], "after lunch")
        self.assertEqual(projected["custom_module"], original["research"]["custom_module"])
        self.assertEqual(projected["itinerary"]["planner_note"], "preserve itinerary metadata")
        self.assertEqual(projected["places"][0]["coordinates"]["precision_note"], "unknown source precision")
        self.assertIsNone(projected["places"][0]["rating"]["value"])
        self.assertTrue(loaded.decisions[0].selection_locked)
        self.assertFalse(loaded.decisions[-1].is_scheduled)

    def test_import_is_idempotent_and_changed_import_cannot_overwrite_a_lock(self):
        payload = legacy_fixture()
        bundle = normalize_legacy_trip(payload, owner_id=OWNER_A)
        with self.engine.begin() as connection:
            import_trip(connection, bundle)
            self.assertEqual(import_trip(connection, bundle)["status"], "already_imported")
            payload["research"]["places"][0]["name"] = "Changed"
            changed = normalize_legacy_trip(payload, owner_id=OWNER_A)
            with self.assertRaises(ImportConflict):
                import_trip(connection, changed)
            loaded = load_trip(connection, trip_id=bundle.id, owner_id=OWNER_A)
            self.assertEqual(loaded.places[0].name, "First museum")
            self.assertTrue(loaded.decisions[0].selection_locked)

    def test_failed_import_rolls_back_even_if_caller_catches_the_exception(self):
        trip = normalize_legacy_trip(legacy_fixture(), owner_id=OWNER_A)
        with self.engine.begin() as connection:
            connection.execute(insert(s.app_users), {"id": OWNER_B})
            connection.execute(insert(s.user_places), {"id": str(trip.places[1].id), "owner_id": OWNER_B, "name": "Unrelated"})
            with self.assertRaises(IntegrityError):
                import_trip(connection, trip)
            self.assertIsNone(connection.execute(select(s.trips.c.id).where(s.trips.c.id == str(trip.id))).first())
            self.assertEqual(connection.execute(select(s.user_places.c.name)).scalar_one(), "Unrelated")

    def test_pending_legacy_claims_are_not_fresh_or_confirmed(self):
        trip = normalize_legacy_trip(legacy_fixture(), owner_id=OWNER_A)
        with self.engine.begin() as connection:
            import_trip(connection, trip)
            observation = connection.execute(select(s.observations)).mappings().first()
            self.assertIsNone(observation["observed_at"])
            self.assertEqual(observation["verification_status"], "unverified")
            self.assertEqual(connection.execute(select(s.source_policies.c.status)).scalar_one(), "pending")

    def test_downgrade_requires_explicit_destructive_opt_in(self):
        with self.assertRaisesRegex(RuntimeError, "Downgrade deletes data"):
            command.downgrade(self.config, "base")
        self.assertIn("trips", inspect(self.engine).get_table_names())
        self.config.cmd_opts = argparse.Namespace(x=["allow_destructive_downgrade=true"])
        command.downgrade(self.config, "base")
        self.assertEqual(inspect(self.engine).get_table_names(), ["alembic_version"])

    def test_postgresql_migration_sql_parses_and_never_initializes_a_connection(self):
        from pglast import parse_sql, parse_plpgsql
        from trippy.data.rls_v1 import SPATIAL_DDL
        output = io.StringIO()
        config = Config(str(ROOT / "alembic.ini"), output_buffer=output)
        config.cmd_opts = argparse.Namespace(x=["dialect=postgresql"])
        with patch("trippy.data.database.make_engine", side_effect=AssertionError("SQL preview connected")):
            command.upgrade(config, "head", sql=True)
        sql = output.getvalue()
        self.assertGreater(len(parse_sql(sql)), 100)
        parse_plpgsql(SPATIAL_DDL)
        self.assertIn("FORCE ROW LEVEL SECURITY", sql)
        self.assertIn("scope_key", sql)
        self.assertNotIn("ALL TABLES IN SCHEMA", sql, "Do not change permissions on unrelated existing tables")


class CompatibilityTests(unittest.TestCase):
    def test_cli_preview_is_private_lossless_and_does_not_connect(self):
        import trippy.migrate_legacy as cli
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "library.json"
            original = b"\xef\xbb\xbf" + json.dumps([legacy_fixture()], indent=2).replace("\n", "\r\n").encode()
            source.write_bytes(original)
            output = Path(directory) / "preview"
            with patch("sys.argv", ["migrate_legacy", "--input", str(source), "--owner-id", OWNER_A,
                                     "--output-dir", str(output)]), patch("sys.stdout", new_callable=io.StringIO), \
                    patch.object(cli, "make_engine", side_effect=AssertionError("Preview opened a database")) as engine:
                self.assertEqual(cli.main(), 0)
                self.assertEqual(cli.main(), 0)
            engine.assert_not_called()
            backup = next(output.glob("backup-*.json"))
            self.assertEqual(backup.read_bytes(), original)
            self.assertEqual(source.read_bytes(), original)
            self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o600)

    def test_candidate_targets_are_explicit_private_or_canonical_references(self):
        from trippy.contracts import Candidate
        candidate_id, place_id, entity_id = uuid4(), uuid4(), uuid4()
        self.assertEqual(Candidate(id=candidate_id, entity_id=entity_id).entity_id, entity_id)
        for targets in ({}, {"user_place_id": place_id, "entity_id": entity_id}):
            with self.subTest(targets=targets), self.assertRaises(ValueError):
                Candidate(id=candidate_id, **targets)

    def test_ids_survive_place_swaps_and_differ_between_owners(self):
        payload = legacy_fixture()
        first = normalize_legacy_trip(payload, owner_id=OWNER_A)
        payload["research"]["itinerary"]["days"][0]["stops"][0]["place_id"] = "P2"
        second = normalize_legacy_trip(payload, owner_id=OWNER_A)
        self.assertEqual([d.id for d in first.decisions], [d.id for d in second.decisions])
        self.assertEqual([p.id for p in first.places], [p.id for p in second.places])
        self.assertNotEqual(second.id, normalize_legacy_trip(payload, owner_id=OWNER_B).id)

    def test_v2_patch_is_additive_preserves_extensions_and_cannot_change_user_state(self):
        foundation = legacy_fixture()["research"]
        snapshot = copy.deepcopy(foundation)
        patch_document = {"schema_version": "trippy-research-patch-v2", "upsert": {
            "places": [{"id": "P1", "description": "New"}, {"id": "P3", "name": "Third", "category": "museum"}]}}
        merged = merge_legacy_patch(foundation, patch_document)
        self.assertEqual(foundation, snapshot)
        self.assertEqual(merged["places"][0]["custom_field"], "keep me")
        self.assertEqual(len(merged["places"]), 3)
        with self.assertRaises(ValueError):
            merge_legacy_patch(foundation, {"schema_version": "trippy-research-patch-v2", "set": {"app_owned_state": {}}})

    def test_v1_additive_patch_keeps_existing_ids(self):
        foundation = legacy_fixture()["research"]
        merged = merge_legacy_patch(foundation, {"schema_version": "trippy-research-patch-v1",
            "add_places": [{"id": "P1", "name": "Overwrite attempt"}, {"id": "P3", "name": "New"}]})
        self.assertEqual(merged["places"][0]["name"], "First museum")
        self.assertEqual(len(merged["places"]), 3)

    def test_invalid_unknown_reference_and_coordinate_do_not_become_guesses(self):
        for value in (True, float("nan"), 91):
            payload = legacy_fixture()
            payload["research"]["places"][0]["coordinates"] = {"latitude": value, "longitude": 2}
            with self.subTest(value=value), self.assertRaises(ValueError):
                normalize_legacy_trip(payload, owner_id=OWNER_A)
        payload = legacy_fixture()
        payload["research"]["places"][0]["source_ids"] = ["MISSING"]
        with self.assertRaises(ValueError):
            normalize_legacy_trip(payload, owner_id=OWNER_A)

    def test_standalone_requires_stable_trip_key_and_preserves_unknown_dates(self):
        document = legacy_fixture()["research"]
        with self.assertRaisesRegex(ValueError, "trip_key"):
            normalize_legacy_trip(document, owner_id=OWNER_A)
        normalized = normalize_legacy_trip(document, owner_id=OWNER_A, trip_key="stable")
        self.assertIsNone(normalized.arrival_date)
        self.assertIsNone(normalized.departure_date)
