import copy
import tempfile
import unittest

from trippy.planner import plan_notes
from trippy.social.gemini import GeminiUnavailable


def plan():
    places = [{'id': 'a', 'name': 'Colosseum', 'category': 'attraction', 'address': 'Piazza del Colosseo, Rome',
               'coordinates': {'latitude': 41.8902, 'longitude': 12.4922}, 'description': ''},
              {'id': 'b', 'name': 'Trattoria Vecchia Roma', 'category': 'food', 'address': 'Via Ferruccio, Rome',
               'coordinates': {'latitude': 41.8950, 'longitude': 12.5030}, 'description': ''}]
    days = [{'date': '2026-12-10', 'theme': 'Η ημέρα σου', 'stops': [
        {'place_id': 'a', 'activity': 'Colosseum', 'time': '10:00'},
        {'place_id': 'b', 'activity': 'Trattoria Vecchia Roma', 'time': '13:00'}]}]
    return {'places': places, 'itinerary': {'days': days}, 'overview': {'summary': 'x'}}


BRIEF = {'destination': 'Rome', 'travelers': {'count': 2}, 'interests': ['attraction', 'food']}


class Pool:
    def __init__(self, payload=None, error=None):
        self.payload, self.error, self.calls, self.texts = payload, error, 0, []

    def generate(self, parts, **kwargs):
        self.calls += 1; self.texts.append(parts[0]['text'])
        if self.error: raise self.error
        return copy.deepcopy(self.payload), 'fake-flash'


NOTES = {'trip_summary': 'Two days of Rome.', 'days': [{'date': '2026-12-10', 'title': 'Ancient Rome on foot today friends', 'summary': 'Ruins, then pasta.'}],
         'stops': [{'id': 'a', 'why': 'The arena everyone pictures.', 'tip': 'Book the first slot.'},
                   {'id': 'b', 'why': 'Carbonara near the ruins.', 'tip': ''},
                   {'id': 'ghost', 'why': 'Invented place', 'tip': ''}]}


class PlanNotesTests(unittest.TestCase):
    def test_one_call_writes_titles_reasons_and_tips(self):
        result, pool = plan(), Pool(NOTES)
        guide = plan_notes.match_guide(result['places'], [{'name': 'Colosseum', 'content': 'Huge amphitheatre.', 'page': 'Rome/Colosseo'}])
        report = plan_notes.annotate(pool, result, BRIEF, guide)
        self.assertEqual(pool.calls, 1)
        self.assertIn('guide: Huge amphitheatre.', pool.texts[0])
        day = result['itinerary']['days'][0]
        self.assertEqual(day['theme'], 'Ancient Rome on foot today…')  # clipped to 5 words
        self.assertEqual(day['stops'][0]['tip'], 'Book the first slot.')
        self.assertNotIn('tip', day['stops'][1])
        self.assertEqual(result['places'][0]['description'], 'Huge amphitheatre.')
        self.assertEqual([s['place_id'] for s in day['stops']], ['a', 'b'])  # schedule untouched, no ghost stop
        self.assertEqual(report['stops_written'], 2)

    def test_failure_leaves_plan_unchanged(self):
        result = plan(); before = copy.deepcopy(result)
        report = plan_notes.annotate(Pool(error=GeminiUnavailable('quota', 123.0)), result, BRIEF, {})
        self.assertEqual(result, before)
        self.assertEqual((report['status'], report['retry_at']), ('failed', 123.0))

    def test_cached_notes_are_not_requested_again(self):
        with tempfile.TemporaryDirectory() as directory:
            pool = Pool(NOTES)
            plan_notes.annotate(pool, plan(), BRIEF, {}, cache_dir=directory)
            report = plan_notes.annotate(pool, plan(), BRIEF, {}, cache_dir=directory)
        self.assertEqual((pool.calls, report['calls']), (1, 0))

    def test_area_character_is_written_in_the_same_call(self):
        result = plan(); result['areas'] = [{'id': 'area-1', 'name': 'Celio', 'place_ids': ['a'], 'days': ['2026-12-10']}]
        result['itinerary']['base'] = {'name': 'Trastevere', 'latitude': 41.889, 'longitude': 12.47}
        notes = dict(NOTES, areas=[{'id': 'area-1', 'character': 'Ruins by day, quiet streets at night.', 'vibe': 'ancient and calm',
                                    'touristy': 5, 'price': 3, 'safety': 9}])
        pool = Pool(notes)
        plan_notes.annotate(pool, result, BRIEF, {})
        self.assertEqual(pool.calls, 1)
        self.assertIn('[area-1] Celio: Colosseum', pool.texts[0])
        self.assertIn('Base: Trastevere', pool.texts[0])
        area = result['areas'][0]
        self.assertEqual((area['touristy'], area['price'], area['vibe']), (5, 3, 'ancient and calm'))
        self.assertNotIn('safety', area)  # out of range scores are dropped

    def test_guide_match_by_name_or_nearby(self):
        places = plan()['places']
        listings = [{'name': 'Vecchia Roma', 'content': 'c', 'latitude': None, 'longitude': None},
                    {'name': 'Colosseo', 'content': 'c', 'latitude': 41.8903, 'longitude': 12.4923}]
        self.assertEqual(set(plan_notes.match_guide(places, listings)), {'b'})


if __name__ == '__main__':
    unittest.main()
