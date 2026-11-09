import unittest

from trippy.planner.gemini_blend import GeminiBlendProvider, same_place
from trippy.planner.planning_contract import normalized_brief, validate_batch

BRIEF = normalized_brief({'destination': 'Athens', 'date_range': {'arrival': '2026-11-20', 'departure': '2026-11-21'},
                          'interests': ['coffee'], 'preference_tags': ['Not touristy'], 'travelers': {'count': 2},
                          'base': {'name': 'Koukaki', 'latitude': 37.9655, 'longitude': 23.7225}})
FOUND = {
    'Upendo': {'id': 'g1', 'name': 'UPENDO ATHENS', 'latitude': 37.966, 'longitude': 23.723, 'types': ['cafe'], 'status': 'OPERATIONAL'},
    'Odeon': {'id': 'g2', 'name': 'Odeon of Herodes Atticus', 'latitude': 37.970, 'longitude': 23.724, 'types': ['tourist_attraction', 'historical_landmark']},
    'Old Cafe': {'id': 'g3', 'name': 'Old Cafe', 'latitude': 37.97, 'longitude': 23.72, 'types': ['cafe'], 'status': 'CLOSED_PERMANENTLY'},
    'Far Cafe': {'id': 'g4', 'name': 'Far Cafe', 'latitude': 40.64, 'longitude': 22.94, 'types': ['cafe']},
}


class GeminiBlendTests(unittest.TestCase):
    def provider(self, names):
        reply = {'places': [{'name': n, 'area': 'Koukaki', 'why': 'Quiet and local.', 'tip': 'Sit by the window.',
                             'price_band': '€', 'touristy': 'low'} for n in names]}
        replies = [reply, {'places': []}]   # the second round (category still short) finds nothing new
        self.prompts = []
        def generate(prompt, system, schema):
            self.prompts.append(prompt); return replies[len(self.prompts) - 1]
        return GeminiBlendProvider(generate, lambda query, destination, near: FOUND.get(query.split(',')[0]))

    def test_keeps_only_real_open_nearby_places_of_the_right_kind(self):
        p = self.provider(['Upendo', 'Odeon', 'Old Cafe', 'Far Cafe', 'Made Up Place'])
        batch = validate_batch(p.discover({'id': 'places-coffee', 'category': 'coffee', 'target': 3}, BRIEF))
        self.assertEqual([x['name'] for x in batch['places']], ['UPENDO ATHENS'])
        self.assertEqual({r['suggested']: r['reason'] for r in p.report},
                         {'Upendo': None, 'Odeon': 'wrong_type', 'Old Cafe': 'closed', 'Far Cafe': 'too_far', 'Made Up Place': 'not_found'})
        self.assertEqual(len(self.prompts), 2)
        self.assertIn("Couldn't be confirmed", self.prompts[1])
        place = batch['places'][0]
        self.assertIn('quality:96', place['tags'])
        self.assertIn('tip:Sit by the window.', place['tags'])
        self.assertEqual(place['why_recommended'], 'Sit by the window.')

    def test_name_matching_tolerates_transliteration(self):
        self.assertTrue(same_place('Filopappou Hill', 'Philopappos Hill'))
        self.assertTrue(same_place('Kerameikos Archaeological Site', 'Archaeological site of Kerameikos'))
        self.assertFalse(same_place('Odeon', 'Takis Bakery'))


if __name__ == '__main__':
    unittest.main()
