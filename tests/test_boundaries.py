"""Neighbourhood boundaries: WKB decoding, offline lookup, retrieval integration."""
import json
from pathlib import Path
import sqlite3
import struct
import tempfile
import unittest

from trippy.catalog.boundaries import AreaIndex, area_contains, area_key, city_slug, parse_wkb
from trippy.planner.travel_provider import LocalCatalogTravelProvider
from tests.test_personal_pipeline import _create_isolated_catalog


def square(x0, y0, x1, y1):
    return [[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]


def area(aid, subtype, names, rings):
    xs = [p[0] for p in rings[0]]; ys = [p[1] for p in rings[0]]
    return {'id': aid, 'subtype': subtype, 'name': names[0], 'names': names,
            'bbox': [min(xs), min(ys), max(xs), max(ys)], 'polygons': [rings]}


def wkb_polygon(rings, endian='<'):
    out = struct.pack(endian + 'bII', 1 if endian == '<' else 0, 3, len(rings))
    for ring in rings:
        out += struct.pack(endian + 'I', len(ring)) + b''.join(struct.pack(endian + 'dd', *p) for p in ring)
    return out


class GeometryTests(unittest.TestCase):
    def test_polygon_and_multipolygon_wkb(self):
        ring = square(0, 0, 1, 1)
        self.assertEqual(parse_wkb(wkb_polygon([ring])), [[ring]])
        self.assertEqual(parse_wkb(wkb_polygon([ring], '>')), [[ring]])
        poly = wkb_polygon([ring])
        multi = struct.pack('<bII', 1, 6, 2) + poly + poly
        self.assertEqual(len(parse_wkb(multi)), 2)

    def test_point_in_polygon_respects_holes(self):
        a = area('a', 'macrohood', ['X'], [square(0, 0, 10, 10), square(4, 4, 6, 6)])
        self.assertTrue(area_contains(a, 1, 1))
        self.assertFalse(area_contains(a, 5, 5))
        self.assertFalse(area_contains(a, 11, 1))


class IndexTests(unittest.TestCase):
    def setUp(self):
        self.city = area('city', 'locality', ['Barcelona'], [square(2.0, 41.3, 2.3, 41.5)])
        self.gracia = area('g', 'macrohood', ['Gràcia', 'Gracia'], [square(2.14, 41.40, 2.17, 41.42)])
        self.goth = area('b', 'microhood', ['el Gòtic', 'Gothic Quarter'], [square(2.17, 41.38, 2.18, 41.39)])
        self.other_centre = area('c', 'neighborhood', ['Centre'], [square(2.4, 41.6, 2.5, 41.7)])
        self.index = AreaIndex('Barcelona', [self.city, self.gracia, self.goth, self.other_centre])

    def test_names_match_without_accents_articles_or_language(self):
        self.assertEqual(self.index.resolve('gracia'), [self.gracia])
        self.assertEqual(self.index.resolve('Gothic Quarter'), [self.goth])
        self.assertEqual(self.index.resolve('Gòtic'), [self.goth])

    def test_names_outside_the_city_polygon_do_not_count(self):
        self.assertEqual(self.index.resolve('Centre'), [])

    def test_names_at_point(self):
        self.assertEqual(self.index.names_at(41.41, 2.15), ['Gràcia'])

    def test_area_mentioned_in_free_text(self):
        self.assertEqual(self.index.mentioned_in('Focus on Gracia food please'), 'Gràcia')
        self.assertEqual(self.index.mentioned_in('a walk in the gothic quarter'), 'el Gòtic')
        self.assertIsNone(self.index.mentioned_in('city centre please'))
        self.assertIsNone(self.index.mentioned_in('graciously'))

    def test_missing_boundary_file_returns_none(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIsNone(AreaIndex.load(d, 'Barcelona'))

    def test_slug_and_key(self):
        self.assertEqual(city_slug('São Paulo'), 'sao-paulo')
        self.assertEqual(area_key("l'Eixample"), 'eixample')


class RetrievalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / '.local').mkdir()
        _create_isolated_catalog(self.root / '.local/catalog.sqlite')

    def tearDown(self):
        self.tmp.cleanup()

    def write_areas(self, areas):
        directory = self.root / '.local/boundaries/barcelona'
        directory.mkdir(parents=True)
        (directory / 'areas.geojsonl').write_text('\n'.join(json.dumps(a) for a in areas))

    def test_polygon_beats_misleading_address_text(self):
        # "Bar Celona Tapas Gracia" sits at 41.401,2.158 with address "Carrer de Gracia 10";
        # the Raval curry house at 41.381,2.169 gets a misleading "Gràcia" street address.
        with sqlite3.connect(self.root / '.local/catalog.sqlite') as db:
            db.execute("UPDATE catalog_snapshots SET address='Passeig de Gràcia 1' WHERE entity_id='ent-food-2'")
        self.write_areas([area('g', 'macrohood', ['Gràcia'], [square(2.15, 41.395, 2.165, 41.41)])])
        batch = LocalCatalogTravelProvider(self.root).discover(
            {'id': 'f', 'category': 'food', 'target': 2, 'area_hint': 'Gràcia'}, {'destination': 'Barcelona'})
        local = [p['name'] for p in batch['places'] if 'area:gracia' in p['tags']]
        outside = [p['name'] for p in batch['places'] if 'area_fallback:gracia' in p['tags']]
        self.assertEqual(local, ['Bar Celona Tapas Gracia'])
        self.assertIn('Raval Curry House', outside)
        self.assertIn('area_match_basis:food:Gràcia:boundary', batch['gaps'])

    def test_city_without_boundaries_reports_text_basis(self):
        batch = LocalCatalogTravelProvider(self.root).discover(
            {'id': 'f', 'category': 'food', 'target': 1, 'area_hint': 'Gracia'}, {'destination': 'Barcelona'})
        self.assertIn('area_match_basis:food:Gracia:address_text', batch['gaps'])


if __name__ == '__main__':
    unittest.main()
