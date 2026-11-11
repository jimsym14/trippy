import pytest

from trippy.planner.gemini_blend import GeminiBlendProvider
from trippy.planner.place_cache import PlaceCache, cached_generate, cached_resolver
from trippy.planner.search_intent import keywords_cover


def _found(name):
    return {'id': 'osm-n' + str(abs(hash(name)) % 10**6), 'name': name, 'names': [name], 'latitude': 41.9, 'longitude': 12.5,
            'types': ['restaurant'], 'status': None, 'address': 'Rome', 'website': None, 'phone': None, 'opening_hours': None, 'maps_url': None}


def _provider(cache, calls):
    def generate(prompt, system, schema):
        calls['ideas'] += 1
        return {'places': [{'name': 'Da Enzo', 'area': 'Trastevere', 'why': 'w', 'tip': 't'},
                           {'name': 'Ghost Kitchen', 'area': 'Nowhere', 'why': 'w', 'tip': 't'}]}

    def resolver(query, destination, near):
        calls['checks'] += 1
        return _found('Da Enzo') if query.startswith('Da Enzo') else None
    resolver.label = 'openstreetmap'
    return GeminiBlendProvider(cached_generate(generate, cache, 'model-a'), [cached_resolver(resolver, cache)])


BRIEF = {'destination': 'Rome', 'travelers': {'count': 2}, 'preference_tags': [], 'vibes': [], 'custom_instructions': '',
         'base': {'name': 'Trastevere', 'latitude': 41.889, 'longitude': 12.47}}
TASK = {'id': 'places-food', 'category': 'food', 'target': 1}


def test_second_identical_plan_makes_no_calls_and_gets_the_same_places():
    cache, calls = PlaceCache(':memory:'), {'ideas': 0, 'checks': 0}
    first = _provider(cache, calls).discover(TASK, BRIEF)
    paid = dict(calls)
    assert paid['ideas'] >= 1 and paid['checks'] >= 2
    second = _provider(cache, calls).discover(TASK, BRIEF)
    assert calls == paid                                    # nothing new was asked of the model or of OpenStreetMap
    assert [p['id'] for p in second['places']] == [p['id'] for p in first['places']] == [_found('Da Enzo')['id']]
    assert cache.stats()['hits']['ideas'] >= 1 and cache.stats()['hits']['checks'] >= 2


def test_a_different_request_asks_again_and_a_base_nearby_reuses_checks():
    cache, calls = PlaceCache(':memory:'), {'ideas': 0, 'checks': 0}
    _provider(cache, calls).discover(TASK, BRIEF)
    paid = dict(calls)
    nearby = {**BRIEF, 'base': {'name': 'Testaccio', 'latitude': 41.876, 'longitude': 12.476}}   # another prompt, same lookup box
    _provider(cache, calls).discover(TASK, nearby)
    assert calls['ideas'] > paid['ideas'] and calls['checks'] == paid['checks']


def test_rows_expire_and_missing_places_are_rechecked_sooner():
    now = [0.0]
    cache = PlaceCache(':memory:', clock=lambda: now[0])
    cache.put('checks', 'found', {'id': 'x'}); cache.put('checks', 'missing', None)
    ttl = lambda value: 30 if value else 7
    now[0] = 8 * 86400
    assert cache.get('checks', 'found', ttl) == (True, {'id': 'x'}) and cache.get('checks', 'missing', ttl) == (False, None)
    now[0] = 31 * 86400
    assert cache.get('checks', 'found', ttl) == (False, None)


def test_google_answers_are_never_cached_and_failed_replies_are_not_kept():
    cache = PlaceCache(':memory:')
    google = lambda query, destination, near: None
    google.label = 'google'
    with pytest.raises(ValueError):
        cached_resolver(google, cache)
    replies = iter([{'places': []}, {'places': [{'name': 'A'}]}])
    generate = cached_generate(lambda *a: next(replies), cache, 'm')
    assert generate('p', 's', {}) == {'places': []} and generate('p', 's', {}) == {'places': [{'name': 'A'}]}


def test_keywords_read_simple_requests_and_leave_nuance_to_the_model():
    assert keywords_cover('tapas and wine, staying in El Born', stay='El Born')
    assert keywords_cover('Θέλουμε μουσεία και καφέ')
    assert keywords_cover('museums, a good viewpoint, coffee near Gràcia', area='Gràcia')
    assert not keywords_cover('somewhere quiet to propose, she hates crowds and loves wine')
    assert not keywords_cover('hello')                      # no theme at all: nothing was understood
    assert not keywords_cover('tapas but nothing with pork, my partner uses a wheelchair')
