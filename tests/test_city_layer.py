"""Free city layer: Wikivoyage parsing, Wikidata classification, linking, retrieval (offline)."""
import json
from pathlib import Path
import tempfile
import unittest

from trippy.catalog.city_layer import Fetcher, grid, parse_listing, _templates
from trippy.planner import city_evidence
from trippy.planner.city_evidence import build, classify, fame
from trippy.planner.travel_provider import LocalCatalogTravelProvider
from tests.test_personal_pipeline import _create_isolated_catalog

CLASSES = {'Q1': 'basilica', 'Q2': 'multifamily residential', 'Q3': 'municipality of Catalonia',
           'Q4': 'metro station', 'Q5': 'park', 'Q6': 'building'}


def item(qid, name, sitelinks, lat, lon, classes, description=None):
    return {'qid': qid, 'sitelinks': sitelinks, 'latitude': lat, 'longitude': lon, 'labels': {'en': name},
            'aliases': [], 'description': description, 'classes': classes, 'website': None, 'image': None}


class ParsingTests(unittest.TestCase):
    def test_listing_template_fields_and_markup(self):
        text = ("intro {{eat | name=[[Can Culleretes]] | alt=Oldest | lat=41.381 | long=2.175 | wikidata=Q123"
                " | address=Carrer d'en Quintana, 5 | url=https://example.org | content=Traditional '''Catalan''' "
                "food since 1786 {{price|€€}}.}} outro {{see|name=No coords}}")
        parsed = [parse_listing(k, b) for k, b in _templates(text)]
        eat = parsed[0]
        self.assertEqual((eat['type'], eat['name'], eat['wikidata']), ('eat', 'Can Culleretes', 'Q123'))
        self.assertEqual((eat['latitude'], eat['longitude']), (41.381, 2.175))
        self.assertEqual(eat['content'], 'Traditional Catalan food since 1786 .')
        self.assertIsNone(parsed[1]['latitude'])

    def test_generic_listing_uses_type_and_rejects_unknown(self):
        self.assertEqual(parse_listing('listing', 'listing|type=drink|name=Bar X')['type'], 'drink')
        self.assertIsNone(parse_listing('listing', 'listing|type=sleep|name=Hotel'))
        self.assertIsNone(parse_listing('see', 'see|name='))

    def test_grid_covers_extent(self):
        points = grid((2.05, 41.30, 2.24, 41.47))
        self.assertTrue(all(41.30 <= p[0] <= 41.47 and 2.05 <= p[1] <= 2.24 for p in points))
        self.assertGreater(len(points), 20)

    def test_fetcher_refuses_unknown_hosts_and_serves_cache(self):
        with tempfile.TemporaryDirectory() as d:
            fetcher = Fetcher(d)
            with self.assertRaises(ValueError):
                fetcher.get('evil.example.com', action='query')


class ClassificationTests(unittest.TestCase):
    def test_types_and_fame_gated_generic_buildings(self):
        self.assertEqual(classify(item('a', 'B', 100, 0, 0, ['Q1']), CLASSES), ('sights', 'landmark'))
        self.assertEqual(classify(item('a', 'Casa', 51, 0, 0, ['Q2']), CLASSES), ('sights', 'landmark'))
        self.assertIsNone(classify(item('a', 'Flat', 10, 0, 0, ['Q2']), CLASSES))
        self.assertIsNone(classify(item('a', 'Town', 90, 0, 0, ['Q3']), CLASSES))
        self.assertIsNone(classify(item('a', 'Stop', 30, 0, 0, ['Q4', 'Q6']), CLASSES))

    def test_fame_scale(self):
        self.assertEqual(fame(4), 0); self.assertEqual(fame(8), 1); self.assertEqual(fame(1000), 4)


class LinkingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        d = self.root / '.local/city_layer/barcelona'; d.mkdir(parents=True)
        (d / 'wikidata.json').write_text(json.dumps({'class_labels': CLASSES, 'items': [
            item('Q10', 'Sagrada Familia', 109, 41.4036, 2.1744, ['Q1'], 'basilica designed by Antoni Gaudí'),
            item('Q11', 'Casa Batlló', 51, 41.3916, 2.1650, ['Q2']),
            item('Q12', 'Parc de la Ciutadella', 25, 41.3881, 2.1873, ['Q5']),
        ]}))
        (d / 'wikivoyage.json').write_text(json.dumps({'pages': [{'title': 'Barcelona', 'url':
            'https://en.wikivoyage.org/wiki/Barcelona', 'listings': [
                {'type': 'eat', 'name': 'Can Culleretes', 'alt': None, 'latitude': 41.3812, 'longitude': 2.1751,
                 'wikidata': None, 'address': "Carrer d'en Quintana, 5", 'url': None,
                 'content': 'Oldest restaurant in town.', 'page': 'Barcelona'},
                {'type': 'see', 'name': 'Sagrada Família', 'alt': None, 'latitude': None, 'longitude': None,
                 'wikidata': 'Q10', 'address': None, 'url': None, 'content': 'Gaudí masterpiece.', 'page': 'Barcelona'},
                {'type': 'see', 'name': 'Nowhere', 'alt': None, 'latitude': None, 'longitude': None,
                 'wikidata': None, 'address': None, 'url': None, 'content': None, 'page': 'Barcelona'},
            ]}]}))
        self.rows = [
            {'entity_id': 'shop', 'name': 'Souvenirs Sagrada Familia', 'family': 'shopping', 'latitude': 41.4035, 'longitude': 2.1745},
            {'entity_id': 'basilica', 'name': 'Sagrada Familia', 'family': 'sights', 'latitude': 41.4032, 'longitude': 2.1749},
            {'entity_id': 'playground', 'name': 'Zona de jocs infantils del Parc de la Ciutadella', 'family': 'outdoors',
             'latitude': 41.3882, 'longitude': 2.1872},
        ]

    def tearDown(self):
        self.tmp.cleanup()

    def test_links_only_same_kind_and_close_names(self):
        built = build(self.root, 'Barcelona', self.rows)
        self.assertEqual(set(built['entities']), {'basilica'})
        basilica = built['entities']['basilica']
        self.assertEqual(basilica['sitelinks'], 109)
        self.assertIn('gaudi', basilica['themes'])
        # The Wikivoyage listing joins the Wikidata item through its QID.
        self.assertEqual(basilica['wikivoyage'][0]['content'], 'Gaudí masterpiece.')
        names = {e['name'] for e in built['standalone']}
        # Not in the catalog (or only as a playground): kept as sourced standalone places.
        self.assertEqual(names, {'Casa Batlló', 'Parc de la Ciutadella', 'Can Culleretes'})

    def test_entries_without_coordinates_never_become_places(self):
        built = build(self.root, 'Barcelona', self.rows)
        self.assertNotIn('Nowhere', {e['name'] for e in built['standalone']})

    def test_retrieval_adds_standalone_with_cited_coordinates(self):
        (self.root / '.local').mkdir(exist_ok=True)
        _create_isolated_catalog(self.root / '.local/catalog.sqlite')
        city_evidence._memory.clear()
        batch = LocalCatalogTravelProvider(self.root).discover(
            {'id': 'a', 'category': 'attraction', 'target': 4}, {'destination': 'Barcelona'})
        batlo = next(p for p in batch['places'] if p['name'] == 'Casa Batlló')
        sources = {s['id']: s for s in batch['sources']}
        self.assertEqual(batlo['id'], 'wd-Q11')
        self.assertEqual(batlo['coordinates']['latitude'], 41.3916)
        self.assertEqual(sources[batlo['coordinates']['source_ids'][0]]['url'], 'https://www.wikidata.org/wiki/Q11')
        self.assertIn('notable:51', batlo['tags'])
        self.assertTrue(batlo['why_recommended'].startswith('Γνωστό σημείο'))
        self.assertIsNone(batlo['rating']['value']); self.assertEqual(batlo['price']['basis'], 'unknown')

    def test_wikivoyage_food_carries_attributed_excerpt(self):
        (self.root / '.local').mkdir(exist_ok=True)
        _create_isolated_catalog(self.root / '.local/catalog.sqlite')
        city_evidence._memory.clear()
        batch = LocalCatalogTravelProvider(self.root).discover(
            {'id': 'f', 'category': 'food', 'target': 3}, {'destination': 'Barcelona'})
        place = next(p for p in batch['places'] if p['name'] == 'Can Culleretes')
        self.assertEqual(place['description'], 'Wikivoyage: Oldest restaurant in town.')
        self.assertIn('wikivoyage_listed', place['tags'])
        publishers = {s['publisher'] for s in batch['sources'] if s['id'] in place['source_ids']}
        self.assertIn('Wikivoyage (CC BY-SA 4.0)', publishers)


if __name__ == '__main__':
    unittest.main()
