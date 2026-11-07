import unittest

from trippy.planner import visits
from trippy.planner.areas import strength
from trippy.planner.osm_places import WikivoyageTravelProvider, stay_from_text
from trippy.planner import scene


def place(pid, name, lat, lon, category='attraction', tags=(), **extra):
    return {'id': pid, 'name': name, 'category': category, 'tags': list(tags), 'rating': {},
            'coordinates': {'latitude': lat, 'longitude': lon}, 'average_visit_minutes': None, **extra}


class DurationTests(unittest.TestCase):
    def test_kind_not_category_sets_the_visit_length(self):
        self.assertEqual(visits.minutes(place('a', 'Circus Maximus', 0, 0, 'museum')), 15)
        self.assertEqual(visits.minutes(place('b', 'Colosseum', 0, 0, 'museum')), 90)
        self.assertEqual(visits.minutes(place('c', 'Trevi Fountain', 0, 0)), 15)
        self.assertEqual(visits.minutes(place('d', 'Basilica of Saint Paul outside the Walls', 0, 0)), 30)
        self.assertGreaterEqual(visits.minutes(place('e', 'Vatican Museums', 0, 0, 'museum', ['notable:65'])), 150)

    def test_open_air_sites_end_by_winter_dusk(self):
        self.assertEqual(visits.closes_by(place('f', 'Roman Forum', 0, 0), 1), 990)
        self.assertEqual(visits.closes_by(place('g', 'Trevi Fountain', 0, 0), 1), 1380)


class GroupTests(unittest.TestCase):
    def test_linked_sights_are_one_visit_but_districts_are_not(self):
        places = [
            place('col', 'Colosseum', 41.8902, 12.4922, tags=['wd:Q10285', 'within:Qpark', 'notable:148']),
            place('arch', 'Arch of Constantine', 41.8898, 12.4906, tags=['wd:Q5786', 'within:Qpark', 'notable:49']),
            place('mus', 'Vatican Museums', 41.9064, 12.4536, 'museum', tags=['wd:Q182955', 'notable:65']),
            place('six', 'Sistine Chapel', 41.9030, 12.4544, tags=['wd:Q2943', 'within:Q145093', 'notable:90']),
            place('far', 'Pantheon', 41.8986, 12.4769, tags=['wd:Q99309']),
        ]
        found = visits.groups(places, strength)
        self.assertEqual(found, {'col': ['arch'], 'mus': ['six']})
        self.assertEqual(visits.group_minutes(places[0], [places[1]]), 105)


class FallbackTests(unittest.TestCase):
    def test_stay_is_read_from_the_note(self):
        self.assertEqual(stay_from_text('Must include: Pantheon. Staying in Trastevere'), 'Trastevere')
        self.assertIsNone(stay_from_text('Must include: Pantheon'))

    def test_wikivoyage_listings_answer_each_category_once(self):
        listings = [
            {'type': 'eat', 'name': 'Da Bucatino', 'latitude': 41.880, 'longitude': 12.476, 'content': 'Traditional Roman dishes.', 'page': 'Rome'},
            {'type': 'eat', 'name': 'Court Delicati', 'latitude': 41.881, 'longitude': 12.486, 'content': 'Chinese food.', 'page': 'Rome'},
            {'type': 'drink', 'name': 'Caffè Sant’Eustachio', 'latitude': 41.898, 'longitude': 12.475, 'content': 'Famous coffee.', 'page': 'Rome'},
            {'type': 'drink', 'name': 'Akab', 'latitude': 41.876, 'longitude': 12.476, 'content': 'Dance club in Testaccio.', 'page': 'Rome'},
        ]
        provider = WikivoyageTravelProvider('.', listings=listings, locate=lambda q: (41.889, 12.474))
        brief = {'destination': 'Rome'}
        names = lambda c: [p['name'] for p in provider.discover({'category': c, 'target': 12}, brief)['places']]
        self.assertEqual(names('food'), ['Da Bucatino', 'Court Delicati'])  # local food first
        self.assertEqual(names('coffee'), ['Caffè Sant’Eustachio'])
        self.assertEqual(names('club'), ['Akab'])
        self.assertEqual(names('bar'), [])


class SceneTests(unittest.TestCase):
    def test_scene_has_the_guide_text_and_reasoned_picks(self):
        result = {'places': [place('b1', 'Szimpla Kert', 47.497, 19.063, 'bar', rating={'value': 4.6, 'review_count': 50000}),
                             place('b2', 'Saved bar', 47.498, 19.06, 'bar', personal_priority=100)],
                  'itinerary': {'days': [{'stops': [{'place_id': 'b1'}]}]}}
        out = scene.build(result, [], {'drink': 'Budapest is known for its ruin bars.', 'source_url': 'https://en.wikivoyage.org/wiki/Budapest'})
        self.assertEqual(out['drink']['text'], 'Budapest is known for its ruin bars.')
        self.assertEqual([p['reason'] for p in out['drink']['picks']], ['Saved by you', '4.6★ on Google from 50,000 reviews'])
        self.assertTrue(out['drink']['picks'][1]['planned'])


if __name__ == '__main__':
    unittest.main()
