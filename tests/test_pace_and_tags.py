"""Speedrun pace and detailed interests (offline, real catalog)."""
from pathlib import Path
import tempfile
import unittest

from trippy.planner.personal_pipeline import run
from trippy.planner.search_intent import tag_themes

ROOT = Path(__file__).resolve().parents[1]


class TagThemeTests(unittest.TestCase):
    def test_detailed_interests_map_to_themes(self):
        self.assertEqual(tag_themes(['tapas', 'cocktail_bars', 'bookshops']), ['cocktails', 'tapas'])
        self.assertEqual(tag_themes(None), [])


@unittest.skipUnless((ROOT / '.local/catalog.sqlite').exists(), 'local catalog required')
class PaceTests(unittest.TestCase):
    def plan(self, **extra):
        brief = {'destination': 'Barcelona', 'planning_strategy': 'personal_places', 'travelers': {'count': 2},
                 'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-06'},
                 'interests': ['attraction', 'food'], **extra}
        with tempfile.TemporaryDirectory() as d:
            return run(brief, directory=d, root=ROOT)

    def test_speedrun_fits_more_short_stops(self):
        fast = self.plan(pace='speedrun')['itinerary']['days']
        normal = self.plan(pace='balanced')['itinerary']['days']
        self.assertGreater(sum(len(d['stops']) for d in fast), sum(len(d['stops']) for d in normal))
        sights = [s for d in fast for s in d['stops'] if s['duration_basis'] == 'estimate']
        self.assertTrue(all(s['duration_minutes'] <= 60 for s in sights))

    def test_detailed_interest_reaches_retrieval(self):
        report = self.plan(preference_tags=['tapas'])['pipeline_report']
        self.assertEqual(report['intent_extraction_path'], 'keyword_fallback')


if __name__ == '__main__':
    unittest.main()
