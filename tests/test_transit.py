from pathlib import Path

from trippy import transit
from trippy.planner.place_cache import PlaceCache

ROOT = Path(__file__).resolve().parents[1]


def _way(points, role=''):
    return {'type': 'way', 'role': role, 'geometry': [{'lat': a, 'lon': b} for a, b in points]}


def _relation(ref, mode, ways, stops=(), colour='#0A84FF', **tags):
    return {'type': 'relation', 'tags': {'type': 'route', 'route': mode, 'ref': ref, 'colour': colour, **tags},
            'members': list(ways) + [{'type': 'node', 'role': 'stop', 'lat': a, 'lon': b} for a, b in stops]}


def test_lines_merge_directions_stitch_ways_and_order_by_mode():
    north = [(37.95, 23.70), (37.96, 23.70), (37.97, 23.70)]
    elements = [
        _relation('T6', 'tram', [_way([(37.94, 23.69), (37.95, 23.69)])]),
        _relation('2', 'subway', [_way(north[1:]), _way(north[:2])], stops=[(37.95, 23.70), (37.97, 23.70)], name='Line 2'),
        _relation('2', 'subway', [_way(north[:2])]),                              # the other direction, shorter: dropped
        _relation('2', 'bus', [_way(north)]),                                     # buses are not drawn
        _relation('9', 'subway', [_way([(37.95, 23.7), (37.9501, 23.7)])]),       # a stub
    ]
    lines = transit.lines_from(elements)
    assert [(l['mode'], l['ref']) for l in lines] == [('subway', '2'), ('tram', 'T6')]
    metro = lines[0]
    assert len(metro['paths']) == 1 and metro['paths'][0][0] == [37.95, 23.7] and metro['paths'][0][-1] == [37.97, 23.7]
    assert metro['color'] == '0A84FF' and len(metro['stops']) == 2 and metro['km'] > 2


def test_lines_are_fetched_once_and_then_come_from_the_cache():
    calls = []
    def fetch(query):
        calls.append(query)
        return [_relation('1', 'subway', [_way([(38.0, 23.7), (38.02, 23.7)])])]
    cache = PlaceCache(':memory:')
    none = ROOT / 'tests/fixtures/no-transit-seeds'                     # no ready-made files: go to Overpass
    first = transit.lines(37.98, 23.73, fetch=fetch, cache=cache, seeds=none)
    again = transit.lines(37.97, 23.74, fetch=fetch, cache=cache, seeds=none)      # same city, another hotel
    assert len(calls) == 1 and again == first and 'subway|light_rail|tram' in calls[0]


def test_advice_picks_the_cheapest_way_to_pay():
    athens = transit.tickets(ROOT, 'Athens, Greece')
    # Three days, four rides a day: the 5-day ticket (8.20) beats 12 singles (14.40) and three day tickets (12.30).
    advice = transit.advise(athens, days=3, rides_per_day=4)
    assert advice['options'][0]['label'] == '5-day ticket' and advice['options'][0]['per_person'] == 8.20 and advice['options'][0]['best']
    # One ride a day: singles win.
    assert transit.advise(athens, days=2, rides_per_day=1)['options'][0]['buy'] == [{'id': 'single', 'count': 2}]
    # With the airport both ways: the 5-day ticket plus two express buses (8.20 + 11.00) just beats the
    # tourist ticket that includes the airport (20.00); both are offered so the traveller can choose the metro.
    flying = transit.advise(athens, days=3, rides_per_day=4, airport=True)
    assert flying['options'][0]['label'] == '5-day ticket' and flying['options'][0]['per_person'] == 19.20
    assert flying['options'][0]['airport_extra'] == 11.00
    tourist = next(o for o in flying['options'] if o['label'] == '3-day tourist ticket')
    assert tourist['per_person'] == 20.00 and tourist['airport_extra'] == 0


def test_bundles_shared_tickets_and_totals_for_a_group():
    barcelona = transit.tickets(ROOT, 'Barcelona')
    advice = transit.advise(barcelona, days=3, rides_per_day=3, travelers=2)   # 9 rides each
    labels = {o['label']: o for o in advice['options']}
    assert labels['1 × T-casual, 10 journeys']['per_person'] == 13.00 and labels['1 × T-casual, 10 journeys']['total'] == 26.00
    assert labels['2 × T-familiar, 8 journeys + 2 singles for everyone']['total'] == 28.80
    assert advice['options'][0]['label'] == '1 × T-casual, 10 journeys'
    assert transit.tickets(ROOT, 'Reykjavik') is None


def test_every_city_names_its_source_and_has_a_single_ticket():
    import json
    table = json.loads((ROOT / 'data/transit/tickets.json').read_text())['cities']
    for key, city in table.items():
        assert key == transit.city_key(city['city']) and city['source'].startswith('http') and city['checked']
        assert any(t['kind'] == 'single' for t in city['tickets'])
        assert all(t['price'] > 0 and t['kind'] in {'single', 'bundle', 'pass', 'pass_plus', 'airport', 'airport_return'} for t in city['tickets'])


def test_direct_lines_are_the_ones_that_stop_near_both_ends():
    def relation(mode, ref, **tags):
        return {'type': 'relation', 'tags': {'type': 'route', 'route': mode, 'ref': ref, 'network': 'OASA', **tags}}
    replies = {'37.968': [relation('bus', '040', colour='#0055AA'), relation('bus', '040'), relation('subway', 'M2'), relation('bus', '', name='no number')],
               '37.984': [relation('subway', 'M2'), relation('bus', '224'), relation('coach', 'FLX', service='international')]}
    calls = []
    def fetch(query):
        calls.append(query)
        return next(rows for marker, rows in replies.items() if marker in query)
    cache = PlaceCache(':memory:')
    found = transit.between((37.968, 23.729), (37.984, 23.728), fetch=fetch, cache=cache)
    assert [l['ref'] for l in found['from']] == ['M2', '040'] and found['from'][1]['color'] == '0055AA'      # two directions = one line
    assert [l['ref'] for l in found['direct']] == ['M2'] and found['known']
    assert next(l for l in found['to'] if l['ref'] == 'FLX')['international']
    transit.between((37.968, 23.729), (37.984, 23.728), fetch=fetch, cache=cache)
    assert len(calls) == 2                                                                                    # the second look is free
    def down(query): raise OSError('overpass down')
    assert transit.between((1.0, 1.0), (2.0, 2.0), fetch=down)['known'] is False


def test_reduced_fares_apply_only_where_the_operator_lists_one():
    athens = transit.tickets(ROOT, 'Athens')
    full = transit.advise(athens, days=2, rides_per_day=3)
    reduced = transit.advise(athens, days=2, rides_per_day=3, fare='reduced')
    assert reduced['fare'] == 'reduced' and reduced['options'][0]['label'] == '6 × 90-minute ticket' and reduced['options'][0]['per_person'] == 3.00
    assert full['options'][0]['per_person'] > reduced['options'][0]['per_person']
    # The 24-hour ticket has no reduced price on the operator's page, so it stays at 4.10.
    assert next(o for o in reduced['options'] if '24-hour' in o['label'])['per_person'] == 8.20
    # A city with no reduced fares checked stays on full fare whatever is asked.
    assert transit.advise(transit.tickets(ROOT, 'Rome'), days=2, rides_per_day=3, fare='reduced')['fare'] == 'full'


def _seed_dir(tmp_path, fetched):
    import json
    line = {'id': 'subway:L3', 'mode': 'subway', 'mode_title': 'Metro', 'ref': 'L3', 'name': 'L3', 'color': '33A02C',
            'operator': 'TMB', 'metres': 18000, 'km': 18.0, 'paths': [[[41.37, 2.15], [41.40, 2.17]]], 'stops': [[41.38, 2.16]]}
    (tmp_path / 'barcelona.json').write_text(json.dumps({'city': 'barcelona', 'latitude': 41.3874, 'longitude': 2.1686,
                                                          'fetched': fetched, 'attribution': '© OpenStreetMap contributors', 'lines': [line]}))
    return tmp_path


def test_big_cities_answer_from_a_ready_made_file_without_overpass(tmp_path):
    from datetime import date
    seeds = _seed_dir(tmp_path, date.today().isoformat())
    def fetch(query): raise AssertionError('Overpass should not be called')
    found = transit.lines(41.39, 2.17, fetch=fetch, seeds=seeds)
    assert [l['ref'] for l in found['lines']] == ['L3']
    assert transit.lines(37.98, 23.73, fetch=lambda q: [], seeds=seeds)['lines'] == []   # Athens isn't within 15 km


def test_an_old_ready_made_file_still_beats_a_busy_overpass(tmp_path):
    seeds = _seed_dir(tmp_path, '2020-01-01')
    def busy(query): raise RuntimeError('overpass_busy: runtime error: timeout')
    assert [l['ref'] for l in transit.lines(41.39, 2.17, fetch=busy, seeds=seeds)['lines']] == ['L3']


def test_a_failed_lookup_is_unavailable_not_a_city_without_metro():
    def busy(query): raise RuntimeError('overpass_busy')
    reply = transit.answer(ROOT, 'Nowhere', 10.0, 10.0, fetch=busy)
    assert reply['lines'] == [] and reply['status'] == 'unavailable'


def test_overpass_busy_remark_is_a_failure(monkeypatch):
    import io, json, urllib.request
    from trippy.planner import osm_places
    class Reply(io.BytesIO):
        def __enter__(self): return self
        def __exit__(self, *a): return False
    monkeypatch.setattr(urllib.request, 'urlopen', lambda *a, **k: Reply(json.dumps({'elements': [], 'remark': 'runtime error: Query timed out'}).encode()))
    import pytest
    with pytest.raises(RuntimeError):
        osm_places.overpass('[out:json];')
