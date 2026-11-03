from copy import deepcopy
import unittest

from trippy.planner.evidence import retrieve, validate_stops


class PlannerEvidenceTests(unittest.TestCase):
    def place(self):
        return {'id': 'one', 'name': 'Synthetic museum', 'city_id': 'barcelona',
            'timezone': 'Europe/Madrid',
            'identity': 'confirmed', 'location': 'entrance_verified', 'latitude': 41.4, 'longitude': 2.1,
            'facts': [{'id': 'hours', 'field': 'opening_window', 'value': {'start_minute': 600, 'end_minute': 1080, 'on_date': '2026-11-01'},
                'source_url': 'https://example.org/visit', 'source_kind': 'primary', 'reviewed_on': '2026-10-31',
                'status': 'verified', 'valid_through': '2026-11-02'},
                {'id': 'price', 'field': 'price_per_person', 'value': {'amount': '10', 'currency': 'EUR', 'basis': 'per_person'},
                'source_url': 'https://example.org/prices', 'source_kind': 'primary', 'reviewed_on': '2026-10-31',
                'status': 'verified', 'valid_through': '2026-11-02'}],
            'facets': [{'key': 'interest', 'value': 'museum', 'fact_ids': ['hours'], 'review': 'source_compared_annotation'}]}

    def stop(self):
        return {'decision_id': 'd1', 'place_id': 'one', 'start': '2026-11-01T10:00:00+01:00',
            'duration_minutes': 60, 'duration_basis': 'verified', 'cost_per_person': '10',
            'cost_currency': 'EUR', 'cost_basis': 'verified', 'party_size': 3}

    def test_hard_constraint_rejects_historical_stale_conflicting_and_wrong_scope(self):
        request = {'city_id': 'barcelona', 'on_date': '2026-11-01',
                   'needs': [{'facet': 'interest', 'value': 'museum', 'hard': True}]}
        self.assertEqual(len(retrieve([self.place()], request)['items']), 1)
        for patch in ({'status': 'historical'}, {'status': 'conflict'},
                      {'valid_through': '2026-10-31'}, {'scope': 'internal_room'}):
            place = self.place(); place['facts'][0].update(patch)
            result = retrieve([place], request)
            self.assertFalse(result['items']); self.assertTrue(result['gaps'])

    def test_geographic_name_cannot_satisfy_music_and_exclusions_are_kept(self):
        result = retrieve([self.place()], {'city_id': 'barcelona', 'needs': [{'facet': 'music', 'value': 'goth'}]})
        self.assertFalse(result['items']); self.assertEqual(result['gap_action'], 'targeted_source_research')
        self.assertFalse(retrieve([self.place()], {'city_id': 'barcelona', 'excluded_ids': ['one']})['items'])

    def test_unknown_access_and_wrong_identity_never_validate_schedule(self):
        place = self.place(); place.update(identity='ambiguous', location='source_point')
        self.assertEqual(validate_stops([place], [self.stop()])['state'], 'needs_checks')
        stop = self.stop(); stop['required_fields'] = ['opening_window', 'wheelchair_access_chain']
        result = validate_stops([self.place()], [stop])
        self.assertEqual(result['state'], 'needs_checks')
        self.assertTrue(any(p.get('field') == 'wheelchair_access_chain' for p in result['pending']))

    def test_false_access_and_unbacked_prices_do_not_pass(self):
        place = self.place(); fact = deepcopy(place['facts'][0])
        fact.update(id='access', field='wheelchair_access_chain', value=False)
        place['facts'].append(fact)
        stop = self.stop(); stop['required_fields'] = ['opening_window', 'wheelchair_access_chain']
        self.assertEqual(validate_stops([place], [stop])['state'], 'invalid')
        stop = self.stop(); stop['cost_per_person'] = '1'
        result = validate_stops([self.place()], [stop])
        self.assertFalse(result['cost_complete']); self.assertEqual(result['state'], 'needs_checks')

    def test_utc_start_is_checked_in_barcelona_local_time(self):
        stop = self.stop(); stop['start'] = '2026-11-01T09:00:00+00:00'
        self.assertEqual(validate_stops([self.place()], [stop])['state'], 'validated')

    def test_locks_group_cost_and_opening_window_are_deterministic(self):
        stop = self.stop(); original = deepcopy(stop)
        result = validate_stops([self.place()], [stop], budget='29')
        self.assertEqual(result['known_total'], '30'); self.assertEqual(result['state'], 'invalid')
        self.assertEqual(stop, original)
        stop.update(locked=True, expected_locked_place_id='other', start='2026-11-01T17:30:00+01:00')
        errors = validate_stops([self.place()], [stop])['errors']
        self.assertTrue(any(e['code'] == 'user_lock_changed' for e in errors))
        self.assertTrue(any(e['code'] == 'outside_opening_window' for e in errors))

    def test_route_cannot_be_assumed_and_transfer_overlap_fails(self):
        second = self.stop(); second.update(decision_id='d2', start='2026-11-01T11:00:00+01:00')
        self.assertEqual(validate_stops([self.place()], [self.stop(), second])['state'], 'needs_checks')
        result = validate_stops([self.place()], [self.stop(), second], transfers={('one', 'one'):
            {'minutes': 15, 'status': 'verified', 'on_date': '2026-11-01', 'source_url': 'https://example.org/routes'}})
        self.assertEqual(result['state'], 'invalid')

    def test_empty_plan_is_not_validated(self):
        self.assertEqual(validate_stops([self.place()], [])['state'], 'invalid')


if __name__ == '__main__': unittest.main()
