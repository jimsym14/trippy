"""Candidate quality: suitability prior, creator endorsements, themes, day grouping."""
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

from trippy.planner import endorsements
from trippy.planner.candidate_quality import category_weight, inventory_score
from trippy.planner.plan_engine import slot_rank, quality
from trippy.planner.search_intent import keyword_intent, themes_in
from trippy.planner.travel_provider import LocalCatalogTravelProvider
from tests.test_personal_pipeline import _create_isolated_catalog


def row(**kw):
    base = {'family': 'sights', 'source_category': 'museum', 'confidence': 0.9, 'latitude': 41.38,
            'longitude': 2.17, 'website_url': 'https://example.org', 'name': 'X',
            'source_properties': json.dumps({'sources': [{'dataset': 'meta'}, {'dataset': 'Overture'}]})}
    return {**base, **kw}


def place(pid, lat, lon, q=0, priority=0, tags=()):
    return {'id': pid, 'coordinates': {'latitude': lat, 'longitude': lon}, 'tags': [f'quality:{q:02d}', *tags],
            'personal_priority': priority}


class SuitabilityTests(unittest.TestCase):
    def test_cinemas_and_theatres_are_not_sightseeing(self):
        self.assertIsNone(category_weight('attraction', 'sights', 'movie_theater'))
        self.assertIsNone(category_weight('attraction', 'sights', 'theatre_venue'))
        self.assertIsNotNone(category_weight('attraction', 'outdoors', 'park'))

    def test_tapas_bar_outranks_fast_food(self):
        tapas = inventory_score(row(family='nightlife', source_category='tapas_bar'), 'food')
        fast = inventory_score(row(family='food', source_category='fast_food_restaurant'), 'food')
        self.assertGreater(tapas, fast)

    def test_food_only_takes_tapas_and_wine_bars_from_nightlife(self):
        self.assertIsNone(inventory_score(row(family='nightlife', source_category='cocktail_bar'), 'food'))

    def test_low_confidence_rows_need_an_endorsement(self):
        weak = row(confidence=0.4)
        self.assertIsNone(inventory_score(weak, 'attraction'))
        self.assertIsNotNone(inventory_score(weak, 'attraction', endorsement=3.0))

    def test_distance_from_core_lowers_score(self):
        core = (41.38, 2.17)
        near = inventory_score(row(), 'attraction', core)
        far = inventory_score(row(latitude=41.30, longitude=2.05), 'attraction', core)
        self.assertGreater(near, far)

    def test_endorsement_dominates_inventory_prior(self):
        plain = inventory_score(row(source_category='monument'), 'attraction')
        endorsed = inventory_score(row(source_category='monument', confidence=0.65), 'attraction', endorsement=3.0)
        self.assertGreater(endorsed, plain)


class KeywordIntentTests(unittest.TestCase):
    def test_english_and_greek_requests_map_to_fixed_themes(self):
        self.assertEqual(themes_in('Want Gaudí and tapas'), ['gaudi', 'tapas'])
        self.assertEqual(themes_in('Θέλω παραλία και τάπας'), ['beach', 'tapas'])

    def test_keyword_intent_is_labelled_and_never_names_places(self):
        intent = keyword_intent({'destination': 'Barcelona', 'custom_instructions': 'Gaudí, tapas'})
        self.assertEqual(intent.extraction_path, 'keyword_fallback')
        self.assertEqual(intent.inferred_categories, ['attraction', 'food'])
        self.assertIsNone(intent.area_hint)

    def test_theme_keys_round_trip_through_retrieval(self):
        from trippy.planner.search_intent import THEMES
        # keyword_intent emits theme keys; the provider must accept them as-is.
        self.assertTrue(all(k in THEMES for k in keyword_intent(
            {'destination': 'Barcelona', 'custom_instructions': 'museums and art'}).vibe_tags))

    def test_no_keywords_means_no_keyword_intent(self):
        self.assertIsNone(keyword_intent({'destination': 'Barcelona', 'custom_instructions': 'hello'}))


class SchedulerGroupingTests(unittest.TestCase):
    brief = {'preference_tags': []}

    def test_strongest_candidate_anchors_the_day(self):
        options = [place('a', 41.38, 2.17, q=40), place('b', 41.40, 2.17, q=90)]
        options.sort(key=lambda p: slot_rank(p, None, self.brief))
        self.assertEqual(options[0]['id'], 'b')

    def test_nearby_candidate_beats_slightly_better_far_one(self):
        previous = place('prev', 41.38, 2.17)
        near = place('near', 41.382, 2.172, q=60)
        far = place('far', 41.41, 2.13, q=70)
        self.assertLess(slot_rank(near, previous, self.brief), slot_rank(far, previous, self.brief))

    def test_saved_pin_still_wins_over_distance_and_quality(self):
        previous = place('prev', 41.38, 2.17)
        pin = place('pin', 41.42, 2.12, q=0, priority=100)
        best = place('best', 41.381, 2.171, q=99)
        self.assertLess(slot_rank(pin, previous, self.brief), slot_rank(best, previous, self.brief))

    def test_quality_tag_parsing(self):
        self.assertEqual(quality(place('x', 0, 0, q=57)), 57)
        self.assertEqual(quality({'tags': ['area:gracia']}), 0)


class EndorsementAndRetrievalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / '.local/stage3/planner-release-v1').mkdir(parents=True)
        _create_isolated_catalog(self.root / '.local/catalog.sqlite')
        with sqlite3.connect(self.root / '.local/catalog.sqlite') as db:
            # A mislocated low-confidence duplicate of the museum, and a fast-food row.
            db.execute("""INSERT INTO catalog_snapshots (catalog_version_id, entity_id, source_id, name, search_text,
                family, latitude, longitude, address, website_url, operating_status, shortlist_rank,
                source_category, confidence) VALUES ('cv-1','ent-sight-dup','src-1','Museu Picasso Local',
                'museu picasso local','sights',41.30,2.05,NULL,NULL,NULL,NULL,'museum',0.6)""")
            db.execute("""INSERT INTO catalog_snapshots (catalog_version_id, entity_id, source_id, name, search_text,
                family, latitude, longitude, address, website_url, operating_status, shortlist_rank,
                source_category, confidence) VALUES ('cv-1','ent-food-3','src-1','Burger Spot','burger spot',
                'food',41.382,2.170,'Carrer 1',NULL,NULL,NULL,'fast_food_restaurant',0.9)""")
            db.execute("UPDATE catalog_snapshots SET confidence=0.97 WHERE entity_id='ent-sight-1'")
            db.execute("INSERT INTO entities VALUES ('ent-sight-dup','published')")
            db.execute("INSERT INTO entities VALUES ('ent-food-3','published')")
        venues = [
            self.venue('v1', 'Museu Picasso Local', ['museums'], 'recommended', 'g1',
                       'A must for art lovers; Picasso early works.'),
            self.venue('v2', 'Raval Curry House', ['food'], 'negative', 'g1', 'Avoid.'),
            self.venue('v3', 'Unknown Place', ['sights'], 'recommended', 'g2', 'Nice.'),
        ]
        normalized = self.root / '.local/stage3/normalized.json'
        normalized.write_text(json.dumps({'drafts': venues}))
        (self.root / endorsements.ACTIVE_DATASET).write_text(json.dumps(
            {'normalized': '.local/stage3/normalized.json', 'bundle_sha256': 'test'}))
        endorsements._memory.clear()

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def venue(vid, name, cats, stance, group, opinion):
        return {'id': vid, 'name': name, 'aliases': [], 'kind': 'venue', 'categories': cats, 'stance': stance,
                'publisher_group': group, 'published_at': '2025-01-01',
                'source': {'provider': 'youtube', 'url': f'https://www.youtube.com/watch?v={vid}'},
                'claims': [{'basis': 'creator_opinion', 'value': opinion}]}

    def test_dominant_confident_row_is_linked_and_negative_stance_ignored(self):
        built = endorsements.build(self.root)
        self.assertEqual(list(built['entities']), ['ent-sight-1'])
        entry = built['entities']['ent-sight-1']
        self.assertEqual(entry['review_status'], 'unreviewed')
        self.assertEqual(entry['match_basis'], 'exact_normalized_name_dominant_confidence')
        self.assertIn('art', entry['themes'])
        self.assertEqual([u['name'] for u in built['unmatched']], ['Unknown Place'])

    def test_far_apart_rows_without_a_dominant_one_stay_ambiguous(self):
        with sqlite3.connect(self.root / '.local/catalog.sqlite') as db:
            db.execute("UPDATE catalog_snapshots SET confidence=0.9 WHERE entity_id='ent-sight-1'")
        built = endorsements.build(self.root)
        self.assertEqual(built['entities'], {})
        self.assertEqual([a['name'] for a in built['ambiguous']], ['Museu Picasso Local'])

    def test_reviewer_can_reject_a_link(self):
        (self.root / endorsements.OVERRIDES).write_text(json.dumps({'reject_entity_ids': ['ent-sight-1']}))
        built = endorsements.build(self.root)
        self.assertNotIn('ent-sight-1', built['entities'])

    def test_retrieval_attaches_video_source_but_keeps_catalog_coordinates(self):
        provider = LocalCatalogTravelProvider(self.root)
        batch = provider.discover({'id': 'places-attraction', 'category': 'attraction', 'target': 2},
                                  {'destination': 'Barcelona'})
        names = [p['name'] for p in batch['places']]
        # Same-name mislocated duplicate is collapsed into the strongest row.
        self.assertEqual(names.count('Museu Picasso Local'), 1)
        museum = next(p for p in batch['places'] if p['name'] == 'Museu Picasso Local')
        self.assertEqual(museum['id'], 'ent-sight-1')
        self.assertIn('source_recommended', museum['tags'])
        self.assertIn('identity_link_unreviewed', museum['tags'])
        self.assertEqual(museum['coordinates']['source_ids'], ['catalog-ent-sight-1'])
        video = [s for s in batch['sources'] if s['type'] == 'video']
        self.assertTrue(video and all(s['url'].startswith('https://www.youtube.com/') for s in video))
        self.assertIsNone(museum['rating']['value'])
        self.assertEqual(museum['price']['basis'], 'unknown')

    def test_theme_request_promotes_matching_rows(self):
        provider = LocalCatalogTravelProvider(self.root)
        plain = provider.discover({'id': 'f', 'category': 'food', 'target': 3}, {'destination': 'Barcelona'})
        themed = provider.discover({'id': 'f', 'category': 'food', 'target': 3, 'vibe_tags': ['tapas']},
                                   {'destination': 'Barcelona'})
        tapas = lambda b: next(p for p in b['places'] if p['name'] == 'Bar Celona Tapas Gracia')
        self.assertIn('theme:tapas', tapas(themed)['tags'])
        self.assertGreater(quality(tapas(themed)), quality(tapas(plain)))
        self.assertEqual(themed['places'][-1]['name'], 'Burger Spot')

    def test_bare_theme_key_without_its_own_stem_still_matches(self):
        provider = LocalCatalogTravelProvider(self.root)
        batch = provider.discover({'id': 'm', 'category': 'museum', 'target': 2, 'vibe_tags': ['art']},
                                  {'destination': 'Barcelona'})
        museum = next(p for p in batch['places'] if p['name'] == 'Museu Picasso Local')
        self.assertIn('theme:art', museum['tags'])


if __name__ == '__main__':
    unittest.main()
