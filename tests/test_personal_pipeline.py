"""Stage 1 acceptance tests for the SearchIntent contract and AIAdapter boundary.

These tests prove:
  1. A NL request produces a valid SearchIntent when the adapter succeeds.
  2. Adapter failure (or None return) activates the explicit fallback path.
  3. Inferred categories from intent EXPAND retrieval (more tasks generated).
  4. Explicit brief interests are never removed by intent extraction.
  5. Explicit brief.excluded_place_ids cannot be overridden by intent.
  6. pipeline_report records intent_extraction_path and intent_extraction_model.
  7. The fallback path records 'fallback' — not 'ai_derived'.
  8. intent_enriched_task adds signals without mutating the original task dict.
  9. area_hint enriches GoogleTravelProvider query without replacing destination.

The existing 41-test baseline (test_trip_pipeline.py + test_research_pipeline.py)
is confirmed green by running the full suite — see the Stage 0 report.
"""
import copy
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import MagicMock

from trippy.planner.search_intent import (
    SearchIntent,
    fallback_intent,
    intent_enriched_task,
    merge_intent_categories,
    validate_intent,
)
from trippy.planner.ai_adapter import AIAdapter, AzureIntentAdapter, FallbackOnlyAdapter
from trippy.planner.personal_pipeline import missing_tasks, run as personal_run
from trippy.planner.planning_contract import empty_batch, normalized_brief
from trippy.planner.travel_provider import GoogleTravelProvider, LocalCatalogTravelProvider


# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

BRIEF = {
    'destination': 'Barcelona',
    'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-06'},
    'interests': ['sights'],
    'preference_tags': [],
    'travelers': {'count': 2},
    'pace': 'balanced',
}

BRIEF_WITH_FOOD = {**BRIEF, 'interests': ['sights', 'food']}


def _source():
    return {'id': 'S1', 'url': 'https://example.org/official',
            'publisher': 'Fixture', 'type': 'primary', 'checked_at': '2026-11-02'}


def _place(n, category='attraction'):
    return {
        'id': f'p{n}', 'name': f'Synthetic place {n}', 'category': category,
        'description': 'Fixture only', 'why_recommended': 'Fixture',
        'address': f'Fixture street {n}', 'official_url': 'https://example.org/official',
        'source_ids': ['S1'],
        'coordinates': {'latitude': 41.38 + n * 0.001, 'longitude': 2.17, 'source_ids': ['S1']},
        'identity_status': 'source_matched', 'tags': [],
        'cuisine': None, 'dietary_options': [], 'best_for': [], 'best_time': None,
        'reservation_required': None, 'image_url': None, 'image_source_url': None,
        'image_attribution': None,
        'rating': {'value': None, 'scale': None, 'platform': None, 'review_count': None},
        'price': {'min': None, 'max': None, 'currency': None, 'basis': 'unknown'},
        'price_source_ids': [],
        'average_visit_minutes': 60, 'duration_basis': 'estimate',
    }


def _batch(n=4):
    b = empty_batch()
    b['sources'] = [_source()]
    b['places'] = [_place(i, 'food' if i % 2 else 'attraction') for i in range(n)]
    b['date_checks'] = [
        {'entity_id': p['id'], 'local_date': d, 'status': 'confirmed',
         'opening_windows': [{'start': '09:00', 'end': '23:00'}],
         'details': 'Fixture', 'source_ids': ['S1'], 'checked_at': '2026-11-02'}
        for p in b['places'] for d in ['2026-12-05', '2026-12-06']
    ]
    b['calendar_checks'] = [
        {'date': d, 'status': 'researched', 'details': 'Fixture',
         'source_ids': ['S1'], 'checked_at': '2026-11-02'}
        for d in ['2026-12-05', '2026-12-06']
    ]
    b['transport_options'] = [{
        'id': 'T1', 'name': 'Fixture transit', 'best_for': 'Fixture',
        'price': {'min': None, 'max': None, 'currency': 'EUR', 'basis': 'unknown'},
        'official_url': 'https://example.org/official', 'source_ids': ['S1'], 'limitations': [],
    }]
    return b


def _create_isolated_catalog(db_path):
    with sqlite3.connect(db_path) as db:
        db.executescript("""
            CREATE TABLE geographies (
                id VARCHAR(36) PRIMARY KEY, name TEXT NOT NULL
            );
            CREATE TABLE catalog_versions (
                id VARCHAR(36) PRIMARY KEY, geography_id VARCHAR(36) NOT NULL, status VARCHAR(20) NOT NULL
            );
            CREATE TABLE source_policies (
                id VARCHAR(36) PRIMARY KEY, status VARCHAR(20) NOT NULL,
                allowed_fields JSON NOT NULL,
                can_retain_raw BOOLEAN NOT NULL, can_use_in_prompt BOOLEAN NOT NULL
            );
            CREATE TABLE source_records (
                id VARCHAR(36) PRIMARY KEY, policy_id VARCHAR(36) NOT NULL,
                url TEXT NOT NULL, fetched_at TEXT NOT NULL, owner_id TEXT,
                scope_key VARCHAR(20) NOT NULL, publication_status VARCHAR(20) NOT NULL,
                retention_until TEXT
            );
            CREATE TABLE entities (
                id VARCHAR(36) PRIMARY KEY, publication_status VARCHAR(20) NOT NULL
            );
            CREATE TABLE catalog_snapshots (
                catalog_version_id VARCHAR(36) NOT NULL, entity_id VARCHAR(36) NOT NULL,
                source_id VARCHAR(36) NOT NULL, name TEXT NOT NULL, search_text TEXT NOT NULL,
                family VARCHAR(24) NOT NULL, latitude NUMERIC(10, 7) NOT NULL,
                longitude NUMERIC(10, 7) NOT NULL, address TEXT, website_url TEXT,
                operating_status VARCHAR(32), shortlist_rank INTEGER,
                PRIMARY KEY (catalog_version_id, entity_id)
            );
        """)
        db.execute("INSERT INTO geographies VALUES ('geo-bcn', 'Barcelona')")
        db.execute("INSERT INTO catalog_versions VALUES ('cv-1', 'geo-bcn', 'published')")
        db.execute(
            "INSERT INTO source_policies VALUES ("
            "'pol-1', 'permitted', "
            "'[\"name\", \"coordinates\", \"category\", \"address\", \"website\"]', "
            "1, 1)"
        )
        db.execute("""INSERT INTO source_records VALUES (
            'src-1', 'pol-1', 'https://stac.overturemaps.org/places/collection.json',
            '2026-10-29T18:00:00Z', NULL, 'shared', 'published', NULL
        )""")
        db.execute("INSERT INTO entities VALUES ('ent-food-1', 'published')")
        db.execute("INSERT INTO entities VALUES ('ent-food-2', 'published')")
        db.execute("INSERT INTO entities VALUES ('ent-sight-1', 'published')")
        db.execute("INSERT INTO entities VALUES ('ent-sight-2', 'published')")
        db.execute("""INSERT INTO catalog_snapshots VALUES (
            'cv-1', 'ent-food-1', 'src-1', 'Bar Celona Tapas Gracia', 'bar celona tapas gracia',
            'food', 41.401, 2.158, 'Carrer de Gracia 10', 'https://example.org/tapas',
            NULL, 1
        )""")
        db.execute("""INSERT INTO catalog_snapshots VALUES (
            'cv-1', 'ent-food-2', 'src-1', 'Raval Curry House', 'raval curry house',
            'food', 41.381, 2.169, 'Carrer del Raval 5', 'https://example.org/curry',
            NULL, 2
        )""")
        db.execute("""INSERT INTO catalog_snapshots VALUES (
            'cv-1', 'ent-sight-1', 'src-1', 'Museu Picasso Local', 'museu picasso born',
            'sights', 41.385, 2.181, 'Carrer Montcada 15', 'https://example.org/picasso',
            NULL, 1
        )""")
        db.execute("""INSERT INTO catalog_snapshots VALUES (
            'cv-1', 'ent-sight-2', 'src-1', 'Parc de la Ciutadella Local', 'parc ciutadella born',
            'sights', 41.388, 2.187, 'Passeig de Picasso 1', 'https://example.org/ciutadella',
            NULL, 2
        )""")
        # Columns the production catalog schema always has (NOT NULL there);
        # the provider's suitability score reads them.
        db.executescript("""
            ALTER TABLE catalog_snapshots ADD COLUMN source_category TEXT NOT NULL DEFAULT 'restaurant';
            ALTER TABLE catalog_snapshots ADD COLUMN locality TEXT DEFAULT 'Barcelona';
            ALTER TABLE catalog_snapshots ADD COLUMN confidence NUMERIC(5, 4) DEFAULT 0.9;
            ALTER TABLE catalog_snapshots ADD COLUMN source_properties JSON NOT NULL
                DEFAULT '{"sources": [{"dataset": "meta"}, {"dataset": "Overture"}]}';
            UPDATE catalog_snapshots SET source_category='museum' WHERE entity_id='ent-sight-1';
            UPDATE catalog_snapshots SET source_category='park' WHERE entity_id='ent-sight-2';
        """)


class SucceedingAdapter:
    """Adapter that returns a fixed SearchIntent on every call."""
    name = 'fixture_adapter'

    def __init__(self, intent: SearchIntent):
        self._intent = intent
        self.calls = []

    def extract_intent(self, raw_request, brief):
        self.calls.append(raw_request)
        return self._intent


class FailingAdapter:
    """Adapter that always returns None (simulates any provider failure)."""
    name = 'failing_adapter'

    def __init__(self):
        self.calls = []

    def extract_intent(self, raw_request, brief):
        self.calls.append(raw_request)
        return None


class PlaceProvider:
    """Minimal place provider that returns a fixed batch."""
    name = 'fixture_places'

    def __init__(self, batch=None):
        self._batch = batch or _batch()
        self.queries = []

    def discover(self, task, brief):
        self.queries.append(task)
        return copy.deepcopy(self._batch)


# ---------------------------------------------------------------------------
# 1. SearchIntent schema: validate_intent
# ---------------------------------------------------------------------------

class SearchIntentValidationTests(unittest.TestCase):

    def _brief(self):
        return normalized_brief(BRIEF)

    def test_valid_intent_round_trips(self):
        raw = {
            'inferred_categories': ['museum', 'coffee'],
            'vibe_tags': ['local', 'historic'],
            'area_hint': 'Gràcia',
            'walking_limit_minutes': 15,
            'transport_preference': 'walking',
            'exclusion_hints': ['no fast food'],
        }
        intent = validate_intent(raw, self._brief(), model_name='test-model')
        self.assertEqual(intent.extraction_path, 'ai_derived')
        self.assertEqual(intent.extraction_model, 'test-model')
        self.assertIn('museum', intent.inferred_categories)
        self.assertIn('coffee', intent.inferred_categories)
        self.assertEqual(intent.area_hint, 'Gràcia')
        self.assertEqual(intent.walking_limit_minutes, 15)
        self.assertEqual(intent.transport_preference, 'walking')
        self.assertEqual(intent.exclusion_hints, ['no fast food'])

    def test_forbidden_fields_are_rejected(self):
        """Model must not inject coordinates or place identifiers through intent."""
        for field in ('coordinates', 'latitude', 'longitude', 'place_id', 'address',
                      'price', 'hours', 'rating', 'phone', 'website'):
            with self.subTest(field=field):
                raw = {
                    'inferred_categories': [], 'vibe_tags': [], 'area_hint': None,
                    'walking_limit_minutes': None, 'transport_preference': None,
                    'exclusion_hints': [],
                    field: 'injected',
                }
                with self.assertRaises(ValueError):
                    validate_intent(raw, self._brief())

    def test_unknown_fields_are_rejected(self):
        raw = {
            'inferred_categories': [], 'vibe_tags': [], 'area_hint': None,
            'walking_limit_minutes': None, 'transport_preference': None,
            'exclusion_hints': [], 'extra_field': 'injected',
        }
        with self.assertRaises(ValueError):
            validate_intent(raw, self._brief())

    def test_coordinate_like_area_hint_is_rejected(self):
        raw = {
            'inferred_categories': [], 'vibe_tags': [], 'area_hint': '41.385, 2.173',
            'walking_limit_minutes': None, 'transport_preference': None, 'exclusion_hints': [],
        }
        with self.assertRaises(ValueError):
            validate_intent(raw, self._brief())

    def test_unrecognised_categories_are_silently_dropped(self):
        raw = {
            'inferred_categories': ['museum', 'invented_category_xyz'],
            'vibe_tags': [], 'area_hint': None, 'walking_limit_minutes': None,
            'transport_preference': None, 'exclusion_hints': [],
        }
        intent = validate_intent(raw, self._brief())
        self.assertIn('museum', intent.inferred_categories)
        self.assertNotIn('invented_category_xyz', intent.inferred_categories)

    def test_invalid_transport_preference_rejected(self):
        raw = {
            'inferred_categories': [], 'vibe_tags': [], 'area_hint': None,
            'walking_limit_minutes': None, 'transport_preference': 'teleport',
            'exclusion_hints': [],
        }
        with self.assertRaises(ValueError):
            validate_intent(raw, self._brief())

    def test_walking_limit_out_of_range_rejected(self):
        raw = {
            'inferred_categories': [], 'vibe_tags': [], 'area_hint': None,
            'walking_limit_minutes': 999, 'transport_preference': None, 'exclusion_hints': [],
        }
        with self.assertRaises(ValueError):
            validate_intent(raw, self._brief())

    def test_fallback_intent_records_fallback_path(self):
        brief = normalized_brief(BRIEF)
        intent = fallback_intent(brief)
        self.assertEqual(intent.extraction_path, 'fallback')
        self.assertIsNone(intent.extraction_model)
        self.assertEqual(intent.inferred_categories, [])
        self.assertEqual(intent.destination, 'Barcelona')


# ---------------------------------------------------------------------------
# 2. AIAdapter protocol compliance
# ---------------------------------------------------------------------------

class AIAdapterProtocolTests(unittest.TestCase):

    def test_fallback_only_adapter_satisfies_protocol(self):
        adapter = FallbackOnlyAdapter()
        self.assertIsInstance(adapter, AIAdapter)
        result = adapter.extract_intent('show me cool architecture', normalized_brief(BRIEF))
        self.assertIsNone(result)

    def test_azure_adapter_satisfies_protocol(self):
        mock_provider = MagicMock()
        mock_provider.name = 'mock-azure'
        adapter = AzureIntentAdapter(mock_provider, model_name='gpt-4o-mini')
        self.assertIsInstance(adapter, AIAdapter)
        self.assertEqual(adapter.name, 'gpt-4o-mini')

    def test_azure_adapter_returns_none_on_provider_exception(self):
        """Provider errors must not propagate — planning engine never sees them."""
        mock_provider = MagicMock()
        mock_provider.normalize.side_effect = ConnectionError('fixture timeout')
        adapter = AzureIntentAdapter(mock_provider, model_name='test')
        result = adapter.extract_intent('some request', normalized_brief(BRIEF))
        self.assertIsNone(result)

    def test_azure_adapter_returns_none_on_non_dict_response(self):
        mock_provider = MagicMock()
        mock_provider.normalize.return_value = 'not a dict'
        adapter = AzureIntentAdapter(mock_provider, model_name='test')
        result = adapter.extract_intent('some request', normalized_brief(BRIEF))
        self.assertIsNone(result)

    def test_azure_adapter_returns_none_on_schema_violation(self):
        mock_provider = MagicMock()
        mock_provider.normalize.return_value = {
            'inferred_categories': [], 'vibe_tags': [], 'area_hint': None,
            'walking_limit_minutes': None, 'transport_preference': None,
            'exclusion_hints': [], 'latitude': 41.38,  # forbidden
        }
        adapter = AzureIntentAdapter(mock_provider, model_name='test')
        result = adapter.extract_intent('some request', normalized_brief(BRIEF))
        self.assertIsNone(result)

    def test_azure_adapter_returns_none_for_empty_request(self):
        mock_provider = MagicMock()
        adapter = AzureIntentAdapter(mock_provider, model_name='test')
        result = adapter.extract_intent('', normalized_brief(BRIEF))
        self.assertIsNone(result)
        mock_provider.normalize.assert_not_called()

    def test_azure_adapter_payload_does_not_include_full_brief(self):
        """The model must not receive the full brief — only destination and request."""
        captured = {}
        def capture_normalize(system, payload, schema, task_id):
            captured['payload'] = payload
            return {
                'inferred_categories': [], 'vibe_tags': [], 'area_hint': None,
                'walking_limit_minutes': None, 'transport_preference': None, 'exclusion_hints': [],
            }
        mock_provider = MagicMock()
        mock_provider.normalize.side_effect = capture_normalize
        adapter = AzureIntentAdapter(mock_provider, model_name='test')
        brief = normalized_brief({**BRIEF, 'custom_instructions': 'show me hidden gems'})
        adapter.extract_intent('show me hidden gems', brief)
        self.assertIn('destination', captured['payload'])
        self.assertIn('trip_request', captured['payload'])
        # Full brief fields (locked_stops, excluded_place_ids, etc.) must not be sent.
        self.assertNotIn('locked_stops', captured['payload'])
        self.assertNotIn('excluded_place_ids', captured['payload'])
        self.assertNotIn('library_nodes', captured['payload'])


# ---------------------------------------------------------------------------
# 3. Retrieval helpers
# ---------------------------------------------------------------------------

class RetrievalHelperTests(unittest.TestCase):

    def test_merge_intent_categories_adds_inferred(self):
        """NL inferred categories expand retrieval without removing brief categories."""
        intent = SearchIntent(
            destination='Barcelona',
            inferred_categories=['museum', 'coffee'],
            extraction_path='ai_derived',
        )
        result = merge_intent_categories(['attraction', 'food'], intent)
        self.assertIn('attraction', result)  # explicit brief interest preserved
        self.assertIn('food', result)         # explicit brief interest preserved
        self.assertIn('museum', result)        # inferred addition
        self.assertIn('coffee', result)        # inferred addition

    def test_merge_intent_categories_no_duplicates(self):
        intent = SearchIntent(
            destination='Barcelona',
            inferred_categories=['attraction'],  # already in brief
            extraction_path='ai_derived',
        )
        result = merge_intent_categories(['attraction', 'food'], intent)
        self.assertEqual(result.count('attraction'), 1)

    def test_merge_intent_categories_fallback_intent_does_not_expand(self):
        brief = normalized_brief(BRIEF)
        intent = fallback_intent(brief)
        brief_cats = ['attraction', 'food']
        result = merge_intent_categories(brief_cats, intent)
        self.assertEqual(sorted(result), sorted(brief_cats))

    def test_intent_enriched_task_does_not_mutate_original(self):
        original = {'id': 'places-attraction', 'category': 'attraction', 'target': 4}
        intent = SearchIntent(
            destination='Barcelona',
            area_hint='Gràcia',
            vibe_tags=['local'],
            extraction_path='ai_derived',
        )
        enriched = intent_enriched_task(original, intent)
        self.assertIsNot(enriched, original)
        self.assertNotIn('area_hint', original)   # original untouched
        self.assertEqual(enriched['area_hint'], 'Gràcia')

    def test_intent_enriched_task_carries_all_signals(self):
        intent = SearchIntent(
            destination='Barcelona',
            area_hint='El Born',
            vibe_tags=['romantic', 'historic'],
            transport_preference='walking',
            walking_limit_minutes=10,
            exclusion_hints=['no chains'],
            extraction_path='ai_derived',
        )
        task = intent_enriched_task({'id': 'x', 'category': 'food', 'target': 2}, intent)
        self.assertEqual(task['area_hint'], 'El Born')
        self.assertEqual(task['vibe_tags'], ['romantic', 'historic'])
        self.assertEqual(task['transport_preference'], 'walking')
        self.assertEqual(task['walking_limit_minutes'], 10)
        self.assertEqual(task['exclusion_hints'], ['no chains'])


# ---------------------------------------------------------------------------
# 4. missing_tasks expansion
# ---------------------------------------------------------------------------

class MissingTasksTests(unittest.TestCase):

    def _graph(self, brief):
        from trippy.planner.place_graph import library_graph
        return library_graph(brief, [])

    def test_intent_adds_inferred_categories_to_tasks(self):
        """An inferred category generates a discovery task even if not in interests."""
        brief = normalized_brief(BRIEF)  # interests=['sights'] → ['attraction']
        graph = self._graph(brief)
        intent = SearchIntent(
            destination='Barcelona',
            inferred_categories=['coffee'],  # not in brief
            extraction_path='ai_derived',
        )
        tasks = missing_tasks(brief, graph, intent=intent)
        task_categories = [t['category'] for t in tasks]
        self.assertIn('coffee', task_categories)
        self.assertIn('attraction', task_categories)

    def test_explicit_interests_always_present_regardless_of_intent(self):
        """Brief interests survive even when intent produces an empty category list."""
        brief = normalized_brief(BRIEF_WITH_FOOD)  # interests=['sights','food']
        graph = self._graph(brief)
        intent = SearchIntent(
            destination='Barcelona',
            inferred_categories=[],  # no additions
            extraction_path='ai_derived',
        )
        tasks = missing_tasks(brief, graph, intent=intent)
        task_categories = [t['category'] for t in tasks]
        self.assertIn('attraction', task_categories)
        self.assertIn('food', task_categories)

    def test_no_intent_uses_brief_categories_only(self):
        brief = normalized_brief(BRIEF)
        graph = self._graph(brief)
        tasks_no_intent = missing_tasks(brief, graph, intent=None)
        tasks_fallback = missing_tasks(brief, graph, intent=fallback_intent(brief))
        self.assertEqual(
            sorted(t['category'] for t in tasks_no_intent),
            sorted(t['category'] for t in tasks_fallback),
        )

    def test_ai_derived_intent_attaches_area_hint_to_tasks(self):
        brief = normalized_brief(BRIEF)
        graph = self._graph(brief)
        intent = SearchIntent(
            destination='Barcelona',
            area_hint='Gràcia',
            extraction_path='ai_derived',
        )
        tasks = missing_tasks(brief, graph, intent=intent)
        for task in tasks:
            self.assertEqual(task.get('area_hint'), 'Gràcia')

    def test_fallback_intent_does_not_attach_area_hint(self):
        brief = normalized_brief(BRIEF)
        graph = self._graph(brief)
        intent = fallback_intent(brief)
        tasks = missing_tasks(brief, graph, intent=intent)
        for task in tasks:
            self.assertNotIn('area_hint', task)

    def test_tasks_capped_at_ten(self):
        # Even with many inferred categories the cap holds.
        brief = normalized_brief(BRIEF)
        graph = self._graph(brief)
        intent = SearchIntent(
            destination='Barcelona',
            inferred_categories=['museum', 'coffee', 'bar', 'shopping', 'nature', 'excursion'],
            extraction_path='ai_derived',
        )
        tasks = missing_tasks(brief, graph, intent=intent)
        self.assertLessEqual(len(tasks), 10)


# ---------------------------------------------------------------------------
# 5. Travel provider query enrichment
# ---------------------------------------------------------------------------

class TravelProviderQueryTests(unittest.TestCase):

    def _make_provider(self, captured):
        """Return a GoogleTravelProvider backed by a request spy."""
        def request(path, *, body=None, field_mask=None):
            captured['query'] = body.get('textQuery', '')
            return {'places': []}
        return GoogleTravelProvider(request)

    def test_area_hint_narrows_query_without_replacing_destination(self):
        captured = {}
        provider = self._make_provider(captured)
        brief = normalized_brief(BRIEF)
        task = {
            'id': 'places-food', 'category': 'food', 'target': 4,
            'area_hint': 'El Born',
        }
        provider.discover(task, brief)
        self.assertIn('El Born', captured['query'])
        self.assertIn('Barcelona', captured['query'])

    def test_no_area_hint_uses_destination_only(self):
        captured = {}
        provider = self._make_provider(captured)
        brief = normalized_brief(BRIEF)
        task = {'id': 'places-food', 'category': 'food', 'target': 4}
        provider.discover(task, brief)
        self.assertIn('Barcelona', captured['query'])
        self.assertNotIn('El Born', captured['query'])

    def test_explicit_query_override_takes_priority_over_area_hint(self):
        captured = {}
        provider = self._make_provider(captured)
        brief = normalized_brief(BRIEF)
        task = {
            'id': 'places-food', 'category': 'food', 'target': 4,
            'query': 'tapas bars in Barceloneta',
            'area_hint': 'Gràcia',
        }
        provider.discover(task, brief)
        self.assertEqual(captured['query'], 'tapas bars in Barceloneta')


# ---------------------------------------------------------------------------
# 6. personal_pipeline.run() — Stage 1 acceptance tests
# ---------------------------------------------------------------------------

class PersonalPipelineStage1Tests(unittest.TestCase):

    def _run(self, brief_dict, ai_adapter=None, place_provider=None):
        with tempfile.TemporaryDirectory() as folder:
            return personal_run(
                brief_dict,
                directory=folder,
                root=folder,
                ai_adapter=ai_adapter,
                place_provider=place_provider,
            )

    # --- AT-1: NL request → valid SearchIntent ---

    def test_nl_request_produces_ai_derived_intent(self):
        """AT-1: a custom_instructions field drives ai_derived extraction_path."""
        intent = SearchIntent(
            destination='Barcelona',
            inferred_categories=['museum'],
            extraction_path='ai_derived',
            extraction_model='fixture',
        )
        adapter = SucceedingAdapter(intent)
        brief = {**BRIEF, 'custom_instructions': 'I love impressionist art and local coffee'}
        result = self._run(brief, ai_adapter=adapter)
        report = result['pipeline_report']
        self.assertEqual(report['intent_extraction_path'], 'ai_derived')
        self.assertEqual(report['intent_extraction_model'], 'fixture')
        self.assertIn('museum', report['intent_inferred_categories'])
        self.assertEqual(len(adapter.calls), 1)

    # --- AT-2: Adapter failure → explicit fallback, no fabrication ---

    def test_adapter_failure_uses_fallback_without_corrupting_plan(self):
        """AT-2: provider error activates fallback; plan is still produced."""
        adapter = FailingAdapter()
        brief = {**BRIEF, 'custom_instructions': 'some request'}
        result = self._run(brief, ai_adapter=adapter)
        report = result['pipeline_report']
        self.assertEqual(report['intent_extraction_path'], 'fallback')
        self.assertIsNone(report['intent_extraction_model'])
        # Plan must still be produced (even if partial).
        self.assertIn('itinerary', result)
        self.assertEqual(len(adapter.calls), 1)

    def test_no_adapter_uses_fallback(self):
        """AT-2 (no adapter): pipeline runs with fallback intent when ai_adapter=None."""
        result = self._run(BRIEF, ai_adapter=None)
        self.assertEqual(result['pipeline_report']['intent_extraction_path'], 'fallback')

    # --- AT-3: Explicit constraints cannot be overridden ---

    def test_explicit_excluded_place_ids_not_overridable_by_intent(self):
        """AT-3: exclusion_hints from intent are advisory; excluded_place_ids win."""
        # Build a brief that explicitly excludes a place that also appears in intent hints.
        from trippy.planner.plan_engine import digest
        from trippy.planner.plan_engine import key
        city = key('Barcelona')
        pid_candidate = 'place-' + digest([city, key('Sagrada Família'), key(''), None])[:20]

        intent = SearchIntent(
            destination='Barcelona',
            exclusion_hints=['Sagrada Família'],  # advisory only
            extraction_path='ai_derived',
        )
        adapter = SucceedingAdapter(intent)
        # excluded_place_ids in the brief must remain intact.
        brief = {**BRIEF, 'excluded_place_ids': [pid_candidate],
                 'custom_instructions': 'skip the touristy stuff'}
        result = self._run(brief, ai_adapter=adapter)
        # Verify that excluded_place_ids is still present unchanged in trip_context.
        self.assertIn(pid_candidate, result.get('trip_context', {}).get('excluded_place_ids', []))

    def test_explicit_interests_not_removed_by_intent(self):
        """AT-3: original brief.interests survive even when intent produces extra categories."""
        intent = SearchIntent(
            destination='Barcelona',
            inferred_categories=['coffee'],
            extraction_path='ai_derived',
        )
        adapter = SucceedingAdapter(intent)
        brief = {**BRIEF_WITH_FOOD, 'custom_instructions': 'great coffee spots'}
        result = self._run(brief, ai_adapter=adapter)
        # Both explicit and inferred categories should appear in inferred list.
        report = result['pipeline_report']
        inferred = report['intent_inferred_categories']
        self.assertIn('coffee', inferred)
        # Verify explicit interests still feed planning (food places in plan or retrieval).
        # The brief in trip_context must contain original interests.
        self.assertIn('food', result.get('trip_context', {}).get('interests', []))

    # --- AT-4: Every stop has resolvable identity, name, and coordinates ---

    def test_every_scheduled_stop_has_coordinates(self):
        """AT-4: compose_plan never schedules a stop without coordinates."""
        result = self._run(BRIEF)
        for day in result['itinerary']['days']:
            for stop in day['stops']:
                pid = stop['place_id']
                place = next((p for p in result['places'] if p['id'] == pid), None)
                self.assertIsNotNone(place, f'Stop {pid} has no place record')
                coords = place.get('coordinates', {})
                self.assertIsNotNone(coords.get('latitude'), f'Stop {pid} has no latitude')
                self.assertIsNotNone(coords.get('longitude'), f'Stop {pid} has no longitude')

    # --- AT-5: Sparse inventory → honest partial plan ---

    def test_sparse_inventory_produces_partial_plan_not_fabrication(self):
        """AT-5: no place_provider → partial delivery_status, no invented stops."""
        result = self._run(BRIEF, ai_adapter=None, place_provider=None)
        # Should be partial or failed, never 'ready' with fabricated places.
        self.assertIn(result['delivery_status'], ('partial', 'failed'))
        for day in result['itinerary']['days']:
            for stop in day['stops']:
                pid = stop['place_id']
                place = next((p for p in result['places'] if p['id'] == pid), None)
                self.assertIsNotNone(place)

    # --- AT-6: Unknown hours and prices stay unknown ---

    def test_unknown_hours_and_prices_remain_unknown_not_invented(self):
        """AT-6: plan_engine never fabricates opening hours or prices."""
        result = self._run(BRIEF)
        for place in result['places']:
            # price fields with None min/max must not carry fabricated values.
            price = place.get('price', {})
            if price.get('basis') == 'unknown':
                self.assertIsNone(price.get('min'))
                self.assertIsNone(price.get('max'))

    # --- AT-7: Draft route estimates remain unverified ---

    def test_draft_route_estimates_are_marked_unverified(self):
        """AT-7: server-generated straight-line estimates are never presented as verified."""
        result = self._run(BRIEF)
        for route in result.get('route_previews', []):
            # Either verified is False or the route was returned by a real provider.
            # With no route_provider configured, all must be unverified.
            self.assertFalse(route.get('verified', False),
                             f'Route {route} should not be marked verified without a route provider')

    # --- AT-8: Reproducible ranking and scheduling ---

    def test_same_inputs_produce_same_schedule(self):
        """AT-8: deterministic engine produces identical output for identical inputs."""
        # Use a fixed intent so variability is isolated to the deterministic engine.
        intent = SearchIntent(destination='Barcelona', extraction_path='fallback')
        adapter = SucceedingAdapter(intent)
        # Two independent runs with the same brief.
        result_a = self._run(BRIEF, ai_adapter=adapter)
        result_b = self._run(BRIEF, ai_adapter=adapter)
        stops_a = [
            (d['date'], s['place_id'])
            for d in result_a['itinerary']['days']
            for s in d['stops']
        ]
        stops_b = [
            (d['date'], s['place_id'])
            for d in result_b['itinerary']['days']
            for s in d['stops']
        ]
        self.assertEqual(stops_a, stops_b)

    # --- AT-9: pipeline_report records correct extraction path ---

    def test_pipeline_report_records_ai_derived(self):
        intent = SearchIntent(destination='Barcelona', extraction_path='ai_derived',
                              extraction_model='gpt-4o-mini', inferred_categories=['museum'])
        adapter = SucceedingAdapter(intent)
        # A request the fixed vocabulary can't fully read still goes to the model.
        brief = {**BRIEF, 'custom_instructions': 'museums and coffee, nothing crowded, my mother walks slowly'}
        result = self._run(brief, ai_adapter=adapter)
        self.assertEqual(result['pipeline_report']['intent_extraction_path'], 'ai_derived')
        self.assertFalse(result['pipeline_report']['intent_read_by_keywords'])
        # One it reads completely costs no model call.
        simple = self._run({**BRIEF, 'custom_instructions': 'I want museums and coffee'}, ai_adapter=adapter)
        self.assertEqual(simple['pipeline_report']['intent_extraction_path'], 'keyword_fallback')
        self.assertTrue(simple['pipeline_report']['intent_read_by_keywords'])
        self.assertEqual(result['pipeline_report']['intent_extraction_model'], 'gpt-4o-mini')

    def test_pipeline_report_records_fallback(self):
        adapter = FailingAdapter()
        brief = {**BRIEF, 'custom_instructions': 'any request'}
        result = self._run(brief, ai_adapter=adapter)
        self.assertEqual(result['pipeline_report']['intent_extraction_path'], 'fallback')
        self.assertIsNone(result['pipeline_report']['intent_extraction_model'])

    def test_pipeline_report_records_fallback_when_no_adapter(self):
        result = self._run(BRIEF, ai_adapter=None)
        self.assertEqual(result['pipeline_report']['intent_extraction_path'], 'fallback')


# ---------------------------------------------------------------------------
# 7. Regression: saved pin outranks catalog candidate
# ---------------------------------------------------------------------------

class PlacePriorityRegressionTests(unittest.TestCase):

    def test_saved_pin_has_higher_personal_priority_than_catalog(self):
        """AT-3 (priority): a library pin outranks a catalog-only candidate."""
        from trippy.planner.place_graph import library_graph
        from trippy.planner.plan_engine import merge_batches
        from trippy.planner.planning_contract import validate_batch

        # Build a brief with one library pin.
        pin_node = {
            'id': 'node-pin-1',
            'kind': 'pin',
            'city': 'Barcelona',
            'places': [{'name': 'Pinned Gem', 'latitude': 41.39, 'longitude': 2.17,
                        'selected': True, 'category': 'attraction'}],
        }
        brief = normalized_brief({**BRIEF, 'library_nodes': [pin_node]})
        graph = library_graph(brief, [])

        # The pinned place should have priority = WEIGHTS['pin'] = 100.
        pinned = next((p for p in graph['places'] if p['name'] == 'Pinned Gem'), None)
        self.assertIsNotNone(pinned)
        self.assertEqual(pinned['priority'], 100)

        # A community node (simulated catalog) has priority = WEIGHTS['community'] = 10.
        community_node = {
            'id': 'node-community-1',
            'kind': 'community',
            'city': 'Barcelona',
            'published': True,
            'places': [{'name': 'Community Spot', 'latitude': 41.38, 'longitude': 2.16,
                        'selected': True, 'category': 'attraction'}],
        }
        brief2 = normalized_brief({**BRIEF, 'library_nodes': [pin_node]})
        graph2 = library_graph(brief2, [community_node])
        community = next((p for p in graph2['places'] if p['name'] == 'Community Spot'), None)
        self.assertIsNotNone(community)
        self.assertLess(community['priority'], pinned['priority'])


# ---------------------------------------------------------------------------
# 8. Local catalog provider tests (isolated database)
# ---------------------------------------------------------------------------

class LocalCatalogTravelProviderTests(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        local_dir = self.root / '.local'
        local_dir.mkdir(parents=True)
        _create_isolated_catalog(local_dir / 'catalog.sqlite')
        self.provider = LocalCatalogTravelProvider(self.root)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_local_catalog_discover_returns_valid_batch(self):
        task = {'id': 'places-food', 'category': 'food', 'target': 2}
        batch = self.provider.discover(task, {'destination': 'Barcelona'})
        self.assertGreaterEqual(len(batch['places']), 1)
        place = batch['places'][0]
        self.assertEqual(place['category'], 'food')
        self.assertIsNotNone(place['coordinates']['latitude'])
        self.assertIsNotNone(place['coordinates']['longitude'])
        self.assertEqual(place['identity_status'], 'source_matched')
        self.assertIsNone(place['price']['min'])
        self.assertIsNone(place['price']['max'])
        self.assertEqual(place['price']['basis'], 'unknown')
        self.assertEqual(len(batch['sources']), len(batch['places']))
        self.assertEqual(batch['sources'][0]['publisher'], 'Overture Maps Foundation')

    def test_local_catalog_area_hint_prioritizes_area(self):
        # Gràcia should match Bar Celona Tapas Gracia first
        task = {'id': 'places-food', 'category': 'food', 'target': 1, 'area_hint': 'Gracia'}
        batch = self.provider.discover(task, {'destination': 'Barcelona'})
        self.assertEqual(len(batch['places']), 1)
        self.assertIn('Gracia', batch['places'][0]['name'])
        self.assertIn('area:gracia', batch['places'][0]['tags'])
        self.assertIn('Gracia', batch['places'][0]['why_recommended'])

    def test_local_catalog_insufficient_local_inventory_reports_shortfall(self):
        # Request target 3 in Gracia where only 1 food venue exists in isolated db
        task = {'id': 'places-food', 'category': 'food', 'target': 3, 'area_hint': 'Gracia'}
        batch = self.provider.discover(task, {'destination': 'Barcelona'})
        # Should return 1 local venue + 1 city fallback venue (all that exist in db)
        self.assertEqual(len(batch['places']), 2)
        # First place is local match
        self.assertEqual(batch['places'][0]['name'], 'Bar Celona Tapas Gracia')
        self.assertIn('area:gracia', batch['places'][0]['tags'])
        self.assertIn('Gracia', batch['places'][0]['why_recommended'])
        # Second place is city fallback
        self.assertEqual(batch['places'][1]['name'], 'Raval Curry House')
        self.assertIn('area_fallback:gracia', batch['places'][1]['tags'])
        self.assertIn('εκτός Gracia', batch['places'][1]['why_recommended'])
        # Shortfall and fallback reported in gaps
        self.assertTrue(any('area_inventory_shortfall:food:Gracia:found_1_of_3' in g for g in batch['gaps']))
        self.assertTrue(any('area_inventory_fallback:food:Gracia:using_1_city_candidates' in g for g in batch['gaps']))

    def test_local_catalog_zero_local_inventory_reports_shortfall(self):
        # Request area with zero venues
        task = {'id': 'places-food', 'category': 'food', 'target': 2, 'area_hint': 'NonExistentArea'}
        batch = self.provider.discover(task, {'destination': 'Barcelona'})
        self.assertEqual(len(batch['places']), 2)
        for p in batch['places']:
            self.assertIn('area_fallback:nonexistentarea', p['tags'])
            self.assertIn('εκτός NonExistentArea', p['why_recommended'])
        self.assertTrue(any('area_inventory_shortfall:food:NonExistentArea:found_0_of_2' in g for g in batch['gaps']))
        self.assertTrue(any('area_inventory_fallback:food:NonExistentArea:using_2_city_candidates' in g for g in batch['gaps']))

    def test_local_catalog_missing_file_returns_empty_batch(self):
        with tempfile.TemporaryDirectory() as empty_folder:
            provider = LocalCatalogTravelProvider(empty_folder)
            task = {'id': 'places-food', 'category': 'food', 'target': 4}
            batch = provider.discover(task, {'destination': 'Barcelona'})
            self.assertEqual(batch['places'], [])
            self.assertEqual(batch['sources'], [])


# ---------------------------------------------------------------------------
# 9. End-to-end offline planning (isolated database, no paid APIs)
# ---------------------------------------------------------------------------

class EndToEndOfflinePlanningTests(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        local_dir = self.root / '.local'
        local_dir.mkdir(parents=True)
        _create_isolated_catalog(local_dir / 'catalog.sqlite')

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_end_to_end_offline_planning_with_isolated_catalog(self):
        """Full personal_pipeline.run with local catalog auto-detected, no AI, no network."""
        brief = {
            'destination': 'Barcelona',
            'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-05'},
            'interests': ['food', 'sights'],
            'travelers': {'count': 1},
            'pace': 'balanced',
        }
        job_dir = self.root / 'job-1'
        result = personal_run(brief, directory=job_dir, root=self.root)

        # 1. Place provider auto-detected
        self.assertEqual(result['pipeline_report']['place_provider'], 'local_catalog')
        # 2. Honest delivery status
        self.assertEqual(result['delivery_status'], 'partial')
        # 3. Scheduled stops came from catalog
        scheduled_count = result['pipeline_report']['scheduled_stops']
        self.assertGreaterEqual(scheduled_count, 1)
        # 4. Unknown hours and prices stay unknown
        for p in result['places']:
            self.assertEqual(p['price']['basis'], 'unknown')
            self.assertIsNone(p['price']['min'])
            self.assertIsNone(p['price']['max'])
        # 5. Route estimates are unverified
        for route in result.get('route_previews', []):
            self.assertFalse(route.get('verified', False))
        # 6. Fallback intent recorded honestly
        self.assertEqual(result['pipeline_report']['intent_extraction_path'], 'fallback')

    def test_end_to_end_saved_pin_outranks_catalog_stop(self):
        """A personal pin is scheduled before equivalent catalog candidates."""
        pin_node = {
            'id': 'node-my-pin',
            'kind': 'pin',
            'city': 'Barcelona',
            'places': [{
                'name': 'My Favorite Tapas',
                'latitude': 41.402,
                'longitude': 2.159,
                'selected': True,
                'category': 'food',
            }],
        }
        brief = {
            'destination': 'Barcelona',
            'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-05'},
            'interests': ['food'],
            'library_nodes': [pin_node],
            'travelers': {'count': 1},
            'pace': 'balanced',
        }
        job_dir = self.root / 'job-2'
        result = personal_run(brief, directory=job_dir, root=self.root)
        day1_stops = result['itinerary']['days'][0]['stops']
        self.assertGreaterEqual(len(day1_stops), 1)
        p_map = {p['id']: p for p in result['places']}
        food_stops = [p_map[s['place_id']] for s in day1_stops if p_map[s['place_id']]['category'] == 'food']
        self.assertGreaterEqual(len(food_stops), 1)
        self.assertEqual(food_stops[0]['name'], 'My Favorite Tapas')

    def test_end_to_end_locked_stop_preserved(self):
        """Locked stops cannot be dropped or rescheduled."""
        pin_node = {
            'id': 'node-lock-pin',
            'kind': 'pin',
            'city': 'Barcelona',
            'places': [{
                'id': 'pinned-lock-place',
                'name': 'Locked Morning Spot',
                'address': 'Carrer Mallorca 401',
                'latitude': 41.390,
                'longitude': 2.170,
                'selected': True,
                'category': 'attraction',
            }],
        }
        from trippy.planner.place_graph import library_graph
        graph = library_graph(normalized_brief({
            'destination': 'Barcelona',
            'library_nodes': [pin_node],
        }))
        actual_pid = graph['places'][0]['id']

        brief = {
            'destination': 'Barcelona',
            'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-05'},
            'interests': ['sights'],
            'library_nodes': [pin_node],
            'locked_stops': [{
                'place_id': actual_pid,
                'date': '2026-12-05',
                'time': '11:00',
                'duration_minutes': 90,
            }],
            'travelers': {'count': 1},
            'pace': 'balanced',
        }
        job_dir = self.root / 'job-3'
        result = personal_run(brief, directory=job_dir, root=self.root)
        stops = result['itinerary']['days'][0]['stops']
        locked_stop = next((s for s in stops if s['place_id'] == actual_pid), None)
        self.assertIsNotNone(locked_stop)
        self.assertEqual(locked_stop['time'], '11:00')
        self.assertEqual(locked_stop['duration_minutes'], 90)

    def test_place_without_coordinates_never_scheduled(self):
        """Places missing latitude/longitude must not be scheduled."""
        unlocated_pin = {
            'id': 'node-unlocated',
            'kind': 'pin',
            'city': 'Barcelona',
            'places': [{
                'name': 'Ghost Place Without Coords',
                'latitude': None,
                'longitude': None,
                'selected': False,
                'category': 'food',
            }],
        }
        brief = {
            'destination': 'Barcelona',
            'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-05'},
            'interests': ['food'],
            'library_nodes': [unlocated_pin],
            'travelers': {'count': 1},
            'pace': 'balanced',
        }
        job_dir = self.root / 'job-4'
        result = personal_run(brief, directory=job_dir, root=self.root)
        p_map = {p['id']: p for p in result['places']}
        for day in result['itinerary']['days']:
            for s in day['stops']:
                self.assertNotEqual(p_map[s['place_id']]['name'], 'Ghost Place Without Coords')

    def test_end_to_end_area_hint_schedules_local_candidates_first(self):
        """When local candidates and fallback candidates exist, local candidates are scheduled first."""
        # Request target 2 in Gracia where only 1 food venue exists (Bar Celona Tapas Gracia)
        # and 1 city fallback exists (Raval Curry House).
        fake_intent = SearchIntent(
            destination='Barcelona',
            inferred_categories=['food'],
            area_hint='Gracia',
            extraction_path='ai_derived',
            extraction_model='fake-model',
        )
        brief = {
            'destination': 'Barcelona',
            'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-05'},
            'interests': ['food'],
            'custom_instructions': 'stay in Gracia',
            'travelers': {'count': 1},
            'pace': 'balanced',
        }
        job_dir = self.root / 'job-5'
        result = personal_run(
            brief, directory=job_dir, root=self.root,
            ai_adapter=SucceedingAdapter(fake_intent)
        )
        day1_stops = result['itinerary']['days'][0]['stops']
        self.assertGreaterEqual(len(day1_stops), 1)
        p_map = {p['id']: p for p in result['places']}
        food_stops = [p_map[s['place_id']] for s in day1_stops if p_map[s['place_id']]['category'] == 'food']
        # Local match must come first
        self.assertEqual(food_stops[0]['name'], 'Bar Celona Tapas Gracia')
        self.assertIn('area:gracia', food_stops[0]['tags'])
        # Shortfall must be reported in pipeline_report
        self.assertTrue(any('area_inventory_shortfall' in s for s in result['pipeline_report']['area_shortfalls']))


# ---------------------------------------------------------------------------
# 10. Client integration & boundary tests
# ---------------------------------------------------------------------------

class ClientIntegrationBoundaryTests(unittest.TestCase):

    def test_client_integration_public_response_boundary(self):
        """Public status/result contract expected by the iOS mobile app and bridge consumers."""
        import bridge_server
        from unittest.mock import patch

        brief = {
            'destination': 'Barcelona',
            'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-06'},
            'interests': ['food', 'sights'],
            'planning_strategy': 'personal_places',
        }

        with tempfile.TemporaryDirectory() as folder, \
             patch.object(bridge_server, 'root', return_value=Path(folder)), \
             patch.object(bridge_server, 'state', bridge_server.ResearchState()):

            # Set up isolated catalog so it runs offline cleanly
            local_dir = Path(folder) / '.local'
            local_dir.mkdir(parents=True)
            _create_isolated_catalog(local_dir / 'catalog.sqlite')

            job_id, _ = bridge_server.begin_job(brief)
            bridge_server.run_pipeline(brief, job_id=job_id)
            job = bridge_server.read_job(job_id)

            # Mobile client contract checks
            self.assertIn('step', job)
            expected_step = 'completed' if job['result']['delivery_status'] == 'ready' else 'partial' if job['result']['delivery_status'] == 'partial' else 'error'
            self.assertEqual(job['step'], expected_step)
            result = job['result']
            self.assertIsNotNone(result)

            # Required top-level schema keys expected by iOS JSONSerialization
            for key in ('schema_version', 'trip_context', 'places', 'itinerary', 'sources', 'warnings', 'costs', 'plan_validation', 'pipeline_report'):
                self.assertIn(key, result, f'Missing required client field: {key}')

            # Verify pipeline_report fields do not break client expectations
            report = result['pipeline_report']
            self.assertEqual(report['version'], 'personal-places-v1')
            self.assertIn('scheduled_stops', report)
            self.assertIn('intent_extraction_path', report)
            self.assertIn(report['intent_extraction_path'], ('ai_derived', 'fallback'))
            self.assertIn('place_provider', report)

    def test_paid_research_disabled_never_invokes_google_places(self):
        """When TRIPPY_ALLOW_PAID_RESEARCH is false/unset, GoogleTravelProvider is never initialized."""
        import bridge_server
        from unittest.mock import patch, MagicMock

        brief = {
            'destination': 'Barcelona',
            'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-05'},
            'planning_strategy': 'personal_places',
        }

        mock_google_places_json = MagicMock()
        mock_env = {
            'GOOGLE_PLACES_API_KEY': 'AIzaFakeKeyThatMustNeverBeUsed',
            'TRIPPY_ALLOW_PAID_RESEARCH': 'false',  # Disabled
        }

        with tempfile.TemporaryDirectory() as folder, \
             patch.object(bridge_server, 'root', return_value=Path(folder)), \
             patch.object(bridge_server, 'state', bridge_server.ResearchState()), \
             patch.object(bridge_server, 'read_environment', return_value=mock_env), \
             patch.object(bridge_server, 'google_places_json', mock_google_places_json):

            local_dir = Path(folder) / '.local'
            local_dir.mkdir(parents=True)
            _create_isolated_catalog(local_dir / 'catalog.sqlite')

            job_id, _ = bridge_server.begin_job(brief)
            bridge_server.run_pipeline(brief, job_id=job_id)

            # Ensure zero calls to Google Places API
            mock_google_places_json.assert_not_called()


# ---------------------------------------------------------------------------
# 11. Real local data smoke test (against .local/catalog.sqlite if present)
# ---------------------------------------------------------------------------

class RealLocalDataSmokeTests(unittest.TestCase):

    def test_smoke_real_barcelona_catalog_end_to_end(self):
        """Smoke test using the project's actual .local/catalog.sqlite (Overture).

        Only runs when the 105MB local catalog file is present in the workspace.
        Produces a grounded Barcelona draft with real venues, without network or paid APIs.
        """
        project_root = Path(__file__).resolve().parents[1]
        catalog_path = project_root / '.local/catalog.sqlite'
        if not catalog_path.is_file():
            self.skipTest('Real .local/catalog.sqlite not present on disk')

        brief = {
            'destination': 'Barcelona',
            'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-06'},
            'interests': ['food', 'sights'],
            'custom_instructions': 'focus on Gracia neighbourhood food and sights',
            'travelers': {'count': 2},
            'pace': 'balanced',
        }

        # Deterministic fake adapter extracting valid intent with area_hint
        fake_intent = SearchIntent(
            destination='Barcelona',
            inferred_categories=['food', 'attraction'],
            area_hint='Gràcia',
            vibe_tags=['local'],
            extraction_path='ai_derived',
            extraction_model='fake-deterministic-test-adapter',
        )
        adapter = SucceedingAdapter(fake_intent)

        with tempfile.TemporaryDirectory() as job_folder:
            result = personal_run(
                brief,
                directory=job_folder,
                root=project_root,
                ai_adapter=adapter,
                place_provider=None,  # Must auto-detect LocalCatalogTravelProvider from project_root!
            )

        report = result['pipeline_report']
        self.assertEqual(report['place_provider'], 'local_catalog')
        self.assertEqual(report['intent_extraction_path'], 'ai_derived')
        self.assertEqual(report['intent_extraction_model'], 'fake-deterministic-test-adapter')
        self.assertGreater(report['scheduled_stops'], 0)
        self.assertEqual(len(result['itinerary']['days']), 2)
        # Gràcia has plenty of candidates, so no shortfall expected
        self.assertEqual(report['area_shortfalls'], [])

        # Verify all scheduled stops are real places from Overture in Gràcia
        p_map = {p['id']: p for p in result['places']}
        s_map = {s['id']: s for s in result['sources']}
        for day in result['itinerary']['days']:
            self.assertGreater(len(day['stops']), 0)
            for s in day['stops']:
                place = p_map[s['place_id']]
                lat = place['coordinates']['latitude']
                lon = place['coordinates']['longitude']
                # Barcelona bounding box check
                self.assertTrue(41.0 <= lat <= 42.0, f"Latitude {lat} out of Barcelona bounds")
                self.assertTrue(1.5 <= lon <= 2.5, f"Longitude {lon} out of Barcelona bounds")
                # Source must be one of the catalog's real sources, not invented
                catalog = ('Overture Maps Foundation', 'Wikivoyage', 'Wikidata')
                self.assertTrue(any(s_map[sid]['publisher'].startswith(catalog) for sid in place['source_ids']), place['name'])
                # Geographic relevance: every venue must be an area match for Gràcia
                # Catalog, creator-video, Wikivoyage and Wikidata reasons all name the matched area.
                self.assertTrue(place['why_recommended'].endswith('(Gràcia)'), place['why_recommended'])
                self.assertIn('area:gracia', place['tags'])

        # Verify source attribution
        sources = {s['id']: s for s in result['sources']}
        self.assertTrue(any(s['publisher'] == 'Overture Maps Foundation' for s in sources.values()))

        # Verify honest unknown states
        for p in result['places']:
            self.assertEqual(p['price']['basis'], 'unknown')
            self.assertIsNone(p['price']['min'])
            self.assertIsNone(p['price']['max'])


if __name__ == '__main__':
    unittest.main()

