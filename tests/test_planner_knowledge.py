from pathlib import Path
import tempfile
import unittest

from fastapi.testclient import TestClient
from sqlalchemy import create_engine

from trippy.backend.api import create_app
from trippy.backend.auth import Principal
from trippy.planner.knowledge import Knowledge, build


class Auth:
    def verify(self, token): return Principal('00000000-0000-4000-8000-000000000001')


class KnowledgeTests(unittest.TestCase):
    def observations(self):
        return [{'id': 'coffee', 'name': 'Synthetic café', 'city': 'Barcelona',
            'source_url': 'https://example.org/cafe', 'retrieved_at': '2026-10-31',
            'review_method': 'agent_primary_page_comparison', 'current_trip_verified': False,
            'allergy_safe': None, 'rating': None,
            'coverage_cells': ['specialty_coffee'], 'facts': [{'field': 'subcategory', 'value': 'specialty coffee'}],
            'fit_limit': 'No seating or work permission verified.'}]

    def test_diagnostic_cells_and_source_pages_do_not_clear_release_gates(self):
        document = build(self.observations(), city_id='barcelona', timezone='Europe/Madrid')
        place = document['places'][0]
        self.assertEqual(place['identity'], 'candidate'); self.assertFalse(place['facets'])
        self.assertEqual(place['facts'][0]['status'], 'reviewed_source')
        self.assertFalse(document['gates']['planner_ready'])
        self.assertEqual(place['limitations'], ['No seating or work permission verified.'])
        document['gates']['planner_ready'] = True
        with self.assertRaises(ValueError): Knowledge(document)

    def test_api_requires_auth_and_returns_explicit_partial_state(self):
        knowledge = Knowledge(build(self.observations(), city_id='barcelona', timezone='Europe/Madrid'))
        engine = create_engine('sqlite://')
        with TestClient(create_app(engine, auth=Auth(), planner_knowledge=knowledge)) as client:
            body = {'city_id': 'barcelona', 'needs': [{'facet': 'music', 'value': 'goth'}]}
            self.assertEqual(client.post('/v2/planner/knowledge/search', json=body).status_code, 401)
            result = client.post('/v2/planner/knowledge/search', json=body,
                                 headers={'Authorization': 'Bearer synthetic'}).json()
            self.assertFalse(result['items']); self.assertFalse(result['scheduled'])
            self.assertFalse(result['dataset_planner_ready']); self.assertTrue(result['gaps'])
        engine.dispose()
