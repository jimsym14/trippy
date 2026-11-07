import unittest

from trippy.planner.travel_provider import GoogleTravelProvider, google_rating, hours_tag, opening_hours_from_tags

ROW = {
    'id': 'abc', 'displayName': {'text': 'Bar Rosso'}, 'formattedAddress': 'Via X 1, Rome',
    'location': {'latitude': 41.9, 'longitude': 12.48}, 'rating': 4.6, 'userRatingCount': 812, 'utcOffsetMinutes': 60,
    'regularOpeningHours': {'periods': [
        {'open': {'day': 1, 'hour': 18, 'minute': 0}, 'close': {'day': 2, 'hour': 2, 'minute': 0}},
        {'open': {'day': 5, 'hour': 18, 'minute': 30}, 'close': {'day': 6, 'hour': 3, 'minute': 0}},
    ]},
}


class OpeningHoursTests(unittest.TestCase):
    def test_hours_round_trip_through_tag(self):
        place = {'tags': ['wikivoyage_listed', hours_tag(ROW)]}
        hours = opening_hours_from_tags(place)
        self.assertEqual(place['tags'], ['wikivoyage_listed'])
        self.assertEqual(hours['utc_offset_minutes'], 60)
        self.assertEqual(hours['periods'][1], {'open': {'day': 5, 'hour': 18, 'minute': 30}, 'close': {'day': 6, 'hour': 3, 'minute': 0}})

    def test_always_open(self):
        row = {'regularOpeningHours': {'periods': [{'open': {'day': 0, 'hour': 0, 'minute': 0}}]}}
        hours = opening_hours_from_tags({'tags': [hours_tag(row)]})
        self.assertTrue(hours['always_open'])

    def test_missing_or_bad_hours_add_nothing(self):
        self.assertIsNone(hours_tag({}))
        self.assertIsNone(hours_tag({'regularOpeningHours': {'periods': [{'open': {'day': 1}}]}}))
        self.assertIsNone(opening_hours_from_tags({'tags': ['x']}))

    def test_rating_needs_a_real_value(self):
        self.assertEqual(google_rating(ROW), {'value': 4.6, 'scale': 5, 'platform': 'Google Maps', 'review_count': 812})
        self.assertIsNone(google_rating({'rating': 9})['value'])

    def test_discover_asks_for_hours_in_the_same_call(self):
        calls = []

        def request(path, *, body=None, field_mask=None):
            calls.append(field_mask)
            return {'places': [ROW]}
        batch = GoogleTravelProvider(request).discover({'category': 'bar', 'target': 5}, {'destination': 'Rome'})
        self.assertEqual(len(calls), 1)
        self.assertIn('places.regularOpeningHours', calls[0])
        self.assertTrue(any(t.startswith('hours:v1:60:') for t in batch['places'][0]['tags']))
        self.assertEqual(batch['places'][0]['rating']['value'], 4.6)


if __name__ == '__main__':
    unittest.main()
