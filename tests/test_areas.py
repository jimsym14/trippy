import unittest

from trippy.planner import area_names, areas, famous
from trippy.planner.planning_contract import normalized_brief


def place(pid, lat, lon, category='attraction', fame=0, name=None):
    return {'id': pid, 'name': name or pid, 'category': category, 'tags': [f'notable:{fame}'] if fame else [],
            'coordinates': {'latitude': lat, 'longitude': lon}, 'rating': {}}


# Two clear areas ~3 km apart (an "ancient" one and a "vatican" one) and a lone far place.
ANCIENT = [place('colosseum', 41.8902, 12.4922, fame=148), place('forum', 41.8925, 12.4853, fame=72),
           place('palatine', 41.8892, 12.4875, 'museum', fame=63)]
VATICAN = [place('stpeter', 41.9022, 12.4539, fame=132), place('museums', 41.9065, 12.4536, fame=65)]
FAR = [place('outlier', 41.95, 12.55, fame=30)]


class AreaTests(unittest.TestCase):
    def test_cluster_keeps_walkable_groups_together(self):
        found = areas.cluster(ANCIENT + VATICAN + FAR)
        groups = [set(a['place_ids']) for a in found]
        self.assertIn({'colosseum', 'forum', 'palatine'}, groups)
        self.assertIn({'stpeter', 'museums'}, groups)
        self.assertEqual(found[0]['place_ids'], ['colosseum', 'forum', 'palatine'])  # most important first

    def test_important_areas_get_full_days_and_short_days_stay_near_base(self):
        found = areas.cluster(ANCIENT + VATICAN + FAR)
        base = {'latitude': 41.951, 'longitude': 12.551}  # right next to the outlier
        plan, uncovered = areas.assign(found, ['d1', 'd2', 'd3'], base=base, partial_first=True)
        by_id = {a['id']: set(a['place_ids']) for a in found}
        self.assertEqual(by_id[plan['d1'][0]], {'outlier'})
        self.assertEqual(by_id[plan['d2'][0]], {'colosseum', 'forum', 'palatine'})
        self.assertEqual(by_id[plan['d3'][0]], {'stpeter', 'museums'})
        self.assertEqual(uncovered, [])

    def test_more_areas_than_days_reports_the_uncovered(self):
        found = areas.cluster(ANCIENT + VATICAN + FAR)
        plan, uncovered = areas.assign(found, ['d1'])
        self.assertEqual(len(uncovered), 2)


class FamousTests(unittest.TestCase):
    def test_enrich_tags_matches_adds_misses_and_skips_near_duplicates(self):
        google = {'places': [dict(place('g-pantheon', 41.8986, 12.4769, name='Pantheon'), tags=[])]}
        items = [{'qid': 'Q1', 'name': 'Pantheon', 'latitude': 41.8987, 'longitude': 12.4768, 'sitelinks': 81, 'category': 'attraction'},
                 {'qid': 'Q2', 'name': 'Piazza Navona', 'latitude': 41.8992, 'longitude': 12.4731, 'sitelinks': 47, 'category': 'attraction'},
                 {'qid': 'Q3', 'name': 'Piazza della Rotonda', 'latitude': 41.8990, 'longitude': 12.4769, 'sitelinks': 30, 'category': 'attraction'}]
        batch = famous.enrich([google], items, {'attraction'})
        self.assertIn('notable:81', google['places'][0]['tags'])
        self.assertEqual([p['name'] for p in batch['places']], ['Piazza Navona'])  # Rotonda is the Pantheon's own square
        self.assertEqual(batch['sources'][0]['publisher'], 'Wikidata')


class AreaNameTests(unittest.TestCase):
    def test_names_come_from_lookup_or_the_best_place(self):
        import tempfile
        found = [{'latitude': 41.889, 'longitude': 12.47, 'anchor_name': 'Santa Maria in Trastevere', 'importance': 2},
                 {'latitude': 41.95, 'longitude': 12.55, 'anchor_name': 'Villa Ada', 'importance': 1}]
        lookup = lambda lat, lon: 'Trastevere' if lat < 41.9 else None
        with tempfile.TemporaryDirectory() as root:
            area_names.name_areas(root, found, lookup=lookup, pause=0)
        self.assertEqual([a['name'] for a in found], ['Trastevere', 'around Villa Ada'])


class BaseBriefTests(unittest.TestCase):
    BRIEF = {'destination': 'Rome', 'date_range': {'arrival': '2027-01-09', 'departure': '2027-01-10'}}

    def test_base_is_validated(self):
        ok = normalized_brief({**self.BRIEF, 'base': {'name': 'Trastevere', 'latitude': 41.889, 'longitude': 12.47}})
        self.assertEqual(ok['base']['name'], 'Trastevere')
        with self.assertRaises(ValueError):
            normalized_brief({**self.BRIEF, 'base': {'name': 'x', 'latitude': 200, 'longitude': 0}})


if __name__ == '__main__':
    unittest.main()
