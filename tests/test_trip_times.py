"""Arrival/departure clock times and multi-area requests (offline, real catalog)."""
from pathlib import Path
import tempfile
import unittest

from trippy.planner.personal_pipeline import run

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless((ROOT / '.local/catalog.sqlite').exists(), 'local catalog required')
class TripTimesTests(unittest.TestCase):
    def plan(self, **extra):
        brief = {'destination': 'Barcelona', 'planning_strategy': 'personal_places', 'travelers': {'count': 3},
                 'date_range': {'arrival': '2026-12-05', 'departure': '2026-12-07', **extra.pop('times', {})},
                 'interests': ['attraction', 'food'], **extra}
        with tempfile.TemporaryDirectory() as d:
            return run(brief, directory=d, root=ROOT)

    def test_evening_arrival_and_departure_trim_days(self):
        days = self.plan(times={'arrival_time': '18:45', 'departure_time': '19:40'})['itinerary']['days']
        minutes = lambda s: int(s['time'][:2]) * 60 + int(s['time'][3:])
        self.assertTrue(all(minutes(s) >= 18 * 60 + 45 + 90 for s in days[0]['stops']), days[0]['stops'])
        self.assertTrue(all(minutes(s) + s['duration_minutes'] <= 19 * 60 + 40 - 180 for s in days[-1]['stops']))
        self.assertGreaterEqual(len(days[1]['stops']), 3)

    def test_several_named_areas_are_not_an_area_focus(self):
        text = 'Μένουμε Sant Antoni. Θέλουμε Sagrada Família, Park Güell και Montjuïc.'
        result = self.plan(custom_instructions=text)
        self.assertFalse([w for w in result['warnings'] if w['message'].startswith('area_match_basis')])


if __name__ == '__main__':
    unittest.main()
