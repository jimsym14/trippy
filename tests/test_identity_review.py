from copy import deepcopy
import sqlite3
import tempfile
import unittest
from pathlib import Path

from trippy.sources.identity_review import address_key, propose, read_inventory, review_source_links
from trippy.sources.extraction import fingerprint


class IdentityReviewTests(unittest.TestCase):
    def observation(self):
        return {'id': 'coffee', 'name': 'Nomad Coffee', 'source_url': 'https://nomad.example/locations',
                'facts': [{'field': 'address', 'value': 'Carrer de Sert, 12, 08003 Barcelona'}]}

    def row(self, entity='one', address='Carrer de Sert, 12'):
        return {'entity_id': entity, 'catalog_version_id': 'v1', 'name': 'Nomad Coffee',
                'search_text': 'nomad coffee', 'address': address, 'website_url': 'http://www.nomad.example/',
                'family': 'coffee', 'latitude': 41, 'longitude': 2, 'operating_status': 'open'}

    def test_same_brand_wrong_branch_never_approved(self):
        row = self.row(address='Carrer de Sert, 99')
        group = propose([self.observation()], [row])[0]
        candidate = group['candidates'][0]
        self.assertTrue(candidate['signals']['official_page_host_equals_catalog_website'])
        self.assertEqual(candidate['signals']['address_comparison'], 'conflict_requires_review')
        self.assertIn('identity_not_approved', candidate['blockers'])

    def test_equal_addresses_and_duplicate_ids_remain_separate_proposals(self):
        group = propose([self.observation()], [self.row('one'), self.row('two')])[0]
        self.assertEqual(group['candidate_count_before_limit'], 2)
        self.assertTrue(all(c['status'] == 'proposal_only_not_canonical' for c in group['candidates']))
        truncated = propose([self.observation()], [self.row('one'), self.row('two')], limit=1)[0]
        self.assertTrue(truncated['candidates_truncated'])

    def test_ranges_and_multiple_entrances_are_not_flattened(self):
        self.assertIsNone(address_key('Carrer de Montcada, 15–23'))
        self.assertIsNone(address_key('Main Sert 12; rooms entrance Pujades 95'))
        self.assertIsNone(address_key('Barcelona 08003'))

    def test_no_name_match_does_not_create_place_or_mutate_source(self):
        observation = self.observation(); before = deepcopy(observation)
        row = self.row(); row.update(name='Furniture store', search_text='furniture store', website_url=None)
        group = propose([observation], [row])[0]
        self.assertEqual(group['status'], 'no_catalog_candidate_detected')
        self.assertEqual(observation, before)

    def test_catalog_version_is_geography_scoped(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'catalog.sqlite'
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE catalog_versions(id TEXT,geography_id TEXT)')
                db.execute("INSERT INTO catalog_versions VALUES('v1','another-city')")
            with self.assertRaises(ValueError): read_inventory(path, 'barcelona', 'v1')

    def test_review_cannot_promote_wrong_branch_or_stale_candidate(self):
        for address in ('Carrer de Sert, 99', 'Carrer de Sert, 12'):
            group = propose([self.observation()], [self.row(address=address)])[0]
            document = {'summary': {'review_id': 'test'}, 'groups': [group]}
            decision = {'action': 'link_source_identity', 'observation_id': group['observation_id'],
                'observation_sha256': group['observation_sha256'],
                'candidate_sha256': fingerprint(group['candidates'][0]), 'expected_family': 'coffee',
                'review_method': 'agent_source_catalog_comparison', 'reason': 'Synthetic branch review.'}
            if address.endswith('99'):
                with self.assertRaises(ValueError): review_source_links(document, [decision])
            else:
                result = review_source_links(document, [decision])
                self.assertEqual(result['summary']['reviewed_source_links'], 1)
                self.assertEqual(result['summary']['approved_canonical_places'], 0)
                self.assertFalse(result['summary']['ready_to_publish'])
            with self.assertRaises(ValueError):
                review_source_links(document, [{**decision, 'candidate_sha256': 'stale'}])


if __name__ == '__main__':
    unittest.main()
