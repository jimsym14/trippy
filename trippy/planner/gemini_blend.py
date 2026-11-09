"""Gemini suggests, Google confirms, our engine plans.

The "blend" place provider (switch: TRIPPY_PLACE_PROVIDER=gemini_blend). For each missing category
Gemini Flash-Lite suggests places that fit the request and pills, with a reason and a practical tip,
best first. Every suggestion must resolve to a real, open Google place near the trip before it can
enter the plan, so the model can't invent a place. Ordering and day-building stay in plan_engine.

Tested in the Athens plan lab (8 Nov 2026): it found local places a keyword search missed
(Kerameikos, Diporto, Vyrinis) and cut "touristy" stops.
"""
from datetime import datetime, timezone
import difflib
import math
import re
import unicodedata
from urllib.parse import quote

from .planning_contract import empty_batch
from .osm_hours import hours_tag

LABELS = {'attraction': 'sights, viewpoints and historic places (no restaurants, cafés or bars)', 'food': 'restaurants, tavernas and trattorias for lunch or dinner (no bars or cafés)',
          'coffee': 'cafés and coffee shops only (no restaurants, tavernas, trattorias, bars or sights)', 'museum': 'museums and galleries', 'nature': 'parks, hills and nature', 'shopping': 'shops and markets',
          'bar': 'bars, wine bars and cocktail bars only (no restaurants, trattorias or pizzerias)', 'club': 'night clubs and late-night music', 'excursion': 'day trips'}
# Google place types that can't be the category asked for (catches "Odeon" café → ancient theatre,
# or a restaurant suggested as a sight), unless the place also has a type that fits.
FOOD = {'restaurant', 'cafe', 'coffee_shop', 'bar', 'wine_bar', 'pub', 'bakery', 'meal_takeaway', 'night_club', 'food'}
SIGHTS = {'museum', 'tourist_attraction', 'historical_landmark', 'park', 'natural_feature', 'church', 'art_gallery'}
WRONG_TYPES = {'coffee': SIGHTS, 'food': SIGHTS, 'bar': SIGHTS, 'club': SIGHTS,
               'attraction': FOOD, 'museum': FOOD, 'nature': FOOD}
RIGHT_TYPES = {'coffee': {'cafe', 'coffee_shop', 'bakery'}, 'food': {'restaurant', 'food', 'meal_takeaway'},
               'bar': {'bar', 'wine_bar', 'pub', 'cafe'}, 'club': {'night_club', 'bar'},   # an Italian "bar" is often a café
               'attraction': SIGHTS, 'museum': {'museum', 'art_gallery'}, 'nature': {'park', 'natural_feature'}}
# Fixed reply shape, so the model can't wander off JSON.
SCHEMA = {'type': 'OBJECT', 'properties': {'places': {'type': 'ARRAY', 'items': {'type': 'OBJECT', 'properties': {
    'name': {'type': 'STRING'}, 'local_name': {'type': 'STRING'}, 'street': {'type': 'STRING'}, 'area': {'type': 'STRING'}, 'why': {'type': 'STRING'}, 'tip': {'type': 'STRING'},
    'best_time': {'type': 'STRING'}, 'price_band': {'type': 'STRING'}, 'touristy': {'type': 'STRING', 'enum': ['low', 'medium', 'high']}},
    'required': ['name', 'area', 'why', 'tip']}}}, 'required': ['places']}
SYSTEM = ("You are a local friend who lives in the destination and writes an honest, alternative city blog. "
          "You only name places you are sure exist and are open now. Tips are concrete and from experience: what to order, "
          "when to go, where to sit, what to skip. Never generic praise.")


def folded(text):
    text = unicodedata.normalize('NFKD', text or '').encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9 ]+', ' ', text).split()


def same_place(suggested, found):
    a, b = folded(suggested), folded(found)
    if not a or not b: return True   # Greek-only names fold to nothing: rely on position and type
    if difflib.SequenceMatcher(None, ' '.join(a), ' '.join(b)).ratio() >= 0.55: return True
    stop = {'the', 'cafe', 'coffee', 'bar', 'restaurant', 'taverna', 'tavern', 'hill', 'museum', 'of', 'and', 'o', 'to', 'tou', 'tis'}
    return bool((set(a) - stop) & (set(b) - stop))


def km(a, b):
    dlat, dlng = math.radians(b[0] - a[0]), math.radians(b[1] - a[1])
    h = math.sin(dlat / 2) ** 2 + math.cos(math.radians(a[0])) * math.cos(math.radians(b[0])) * math.sin(dlng / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


class GeminiBlendProvider:
    name = 'gemini_blend'

    def __init__(self, generate, resolve, *, max_km=25):
        """generate(prompt, system, schema) -> dict (JSON). resolve: one resolver or a list tried in order, each
        (query, destination, near) -> {id, name, names?, latitude, longitude, types, status, maps_url, address,
        website?, phone?, opening_hours?} or None."""
        self.generate, self.max_km = generate, max_km
        self.resolvers = list(resolve) if isinstance(resolve, (list, tuple)) else [resolve]
        self.report = []

    def prompt(self, task, brief):
        pills = sorted(set(brief.get('preference_tags', []) + brief.get('vibes', [])))
        base = (brief.get('base') or {}).get('name')
        want = task['target'] + 4
        return (f"Destination: {brief['destination']}. " + (f"Staying in {base}. " if base else '')
                + (f"Focus area: {task['area_hint']}. " if task.get('area_hint') else '')
                + f"Travellers: {brief['travelers']['count']}. Request: {brief.get('custom_instructions') or 'none'}. "
                + (f"Pills chosen: {', '.join(pills)}. " if pills else '')
                + f"Suggest {want} {LABELS.get(task['category'], task['category'])} for this trip, best fit first. "
                + (self.balance(task['category'], pills))
                + 'Return JSON {"places":[{"name":"exact name as on Google Maps","local_name":"name as written on the sign, in the local script",'
                  '"street":"street name","area":"neighbourhood",'
                  '"why":"one specific sentence","tip":"one practical tip","best_time":"e.g. weekday morning",'
                  '"price_band":"€|€€|€€€|€€€€","touristy":"low|medium|high"}]}')

    @staticmethod
    def balance(category, pills):
        local = any('touristy' in p.lower() or 'local' in p.lower() or 'hidden' in p.lower() for p in pills)
        if category in {'attraction', 'museum', 'nature', 'excursion'}:
            # Sights: never drop what a first visit needs; "not touristy" changes how, not whether.
            return ("Start with the city's essential must-sees a first-time visitor shouldn't miss, then add lesser-known gems. "
                    + ("For famous places, the tip says how to avoid the crowds (time, entrance, route). " if local else ''))
        if local:
            return ("Only places locals choose: no tourist traps, no places living off a famous view or a central square. "
                    "Neighbourhood spots, family-run, places with a loyal local crowd. ")
        return "A mix of the best-loved places and good local spots. "

    def check(self, category, name, found, near, seen, local=''):
        if not found: return 'not_found'
        if found.get('status') in {'CLOSED_PERMANENTLY', 'CLOSED_TEMPORARILY'}: return 'closed'
        if not any(same_place(given, n) for given in filter(None, [name, local])
                   for n in [found.get('name', '')] + list(found.get('names') or [])): return 'different_name'
        types = set(found.get('types') or [])
        # Eating and drinking slots need a place known to be one; an unknown kind (an office, a car hire) never fills them.
        if ((types & WRONG_TYPES.get(category, set()) or category in {'food', 'coffee', 'bar', 'club'})
                and not types & RIGHT_TYPES.get(category, set())):
            return 'wrong_type'
        if near and km(near, (found['latitude'], found['longitude'])) > self.max_km: return 'too_far'
        if found['id'] in seen: return 'duplicate'
        return None

    def discover(self, task, brief):
        category = task['category']
        base = brief.get('base') or {}
        near = (base.get('latitude'), base.get('longitude')) if base.get('latitude') is not None else None
        batch, seen, rank, tried = empty_batch(), set(), 0, []
        for round_ in range(2):   # a second round only when checks left the category short
            prompt = self.prompt(task, brief)
            if round_:
                if rank >= task['target']: break
                prompt += (f" Already chosen: {', '.join(p['name'] for p in batch['places']) or 'none'}. "
                           f"Couldn't be confirmed: {', '.join(tried)}. Suggest {task['target'] - rank + 4} different places, "
                           "favouring long-established ones that have been open for years.")
            suggestions = self.ask(prompt)
            tried += [x.get('name', '') for x in suggestions]
            rank = self.take(suggestions, task, brief, category, near, batch, seen, rank)
        return batch

    def ask(self, prompt):
        for attempt in range(2):   # one retry: a reply that isn't valid JSON is rare and random
            try:
                return (self.generate(prompt, SYSTEM, SCHEMA) or {}).get('places') or []
            except ValueError:
                if attempt: raise
        return []

    def take(self, suggestions, task, brief, category, near, batch, seen, rank):
        for s in suggestions:
            name = (s.get('name') or '').strip()
            if not name: continue
            local = (s.get('local_name') or '').strip()
            # Several ways to find it: the name with its area, the local-script name, the name on its street.
            queries = [q for q in dict.fromkeys([name + (', ' + s['area'] if s.get('area') else ''),
                                                 local if local and local != name else '',
                                                 name + ', ' + s['street'] if s.get('street') else '']) if q]
            found, reason, used = None, 'not_found', None
            for resolver in self.resolvers:   # the free check first, the paid one only when it misses
                for query in queries:
                    candidate = resolver(query, brief['destination'], near)
                    reason = self.check(category, name, candidate, near, seen, local)
                    found, used = candidate, getattr(resolver, 'label', 'check')
                    if reason is None or reason not in {'not_found', 'different_name'}: break
                if reason is None: break
            self.report.append({'category': category, 'suggested': name, 'found': (found or {}).get('name'), 'kept': reason is None,
                                'reason': reason, 'checked_by': used})
            if reason: continue
            seen.add(found['id'])
            if found['id'].startswith('osm-'):   # checked on OpenStreetMap: credit it, link the OSM object
                kind = {'n': 'node', 'w': 'way', 'r': 'relation'}.get(found['id'][4:5], 'node')
                sid, publisher = found['id'], 'OpenStreetMap'
                url = f"https://www.openstreetmap.org/{kind}/{found['id'][5:]}"
            else:
                sid, publisher = 'google-' + found['id'], 'Google Maps'
                url = found.get('maps_url') or 'https://www.google.com/maps/search/?api=1&query=' + quote(found['name']) + '&query_place_id=' + quote(found['id'])
            batch['sources'].append({'id': sid, 'url': url, 'publisher': publisher, 'type': 'maps',
                                     'checked_at': datetime.now(timezone.utc).isoformat()})
            tags = [f'quality:{max(60, 96 - 3 * rank)}', 'source:gemini_blend']
            if s.get('touristy') in {'low', 'medium', 'high'}: tags.append('touristy:' + s['touristy'])
            band = s.get('price_band') if s.get('price_band') in {'€', '€€', '€€€', '€€€€'} else None
            if band: tags.append('price_band:' + band)
            if s.get('tip'): tags.append('tip:' + s['tip'][:300])   # kept apart: the notes step rewrites descriptions
            hours = hours_tag(found.get('opening_hours'))
            if hours: tags.append(hours)
            batch['places'].append({'id': found['id'], 'name': found['name'], 'category': category,
                # The reason goes in description; the practical local tip in why_recommended.
                'description': (s.get('why') or '')[:400], 'why_recommended': (s.get('tip') or s.get('why') or '')[:400],
                'address': found.get('address'), 'official_url': found.get('website'), 'source_ids': [sid],
                'coordinates': {'latitude': found['latitude'], 'longitude': found['longitude'], 'source_ids': [sid]},
                'identity_status': 'source_matched', 'tags': tags,
                'price': {'min': None, 'max': None, 'currency': None, 'basis': 'unknown'},
                'price_source_ids': [], 'cuisine': None, 'dietary_options': [], 'best_for': [],
                'best_time': (s.get('best_time') or None), 'reservation_required': None,
                'image_url': None, 'image_source_url': None, 'image_attribution': None,
                'rating': {'value': None, 'scale': None, 'platform': None, 'review_count': None},
                'average_visit_minutes': None, 'duration_basis': 'unknown'})
            rank += 1
            if rank >= task['target'] + 2: break
        return rank


def google_resolver(request):
    """Google check at the lowest price: an IDs-only Text Search (free) near the trip, then Place Details
    Essentials for the position and kind ($0.005). Google doesn't return the name at this tier, so the
    name check relies on Google's own match for the exact name; kind and distance are still checked."""
    def resolve(query, destination, near):
        body = {'textQuery': f'{query}, {destination}', 'pageSize': 1}
        if near: body['locationBias'] = {'circle': {'center': {'latitude': near[0], 'longitude': near[1]}, 'radius': 20000.0}}
        rows = (request('places:searchText', body=body, field_mask='places.id') or {}).get('places') or []
        if not rows or not rows[0].get('id'): return None
        place_id = rows[0]['id']
        row = request('places/' + place_id, field_mask='id,location,types,formattedAddress') or {}
        loc = row.get('location') or {}
        if loc.get('latitude') is None: return None
        return {'id': place_id, 'name': query.split(',')[0], 'latitude': loc['latitude'], 'longitude': loc['longitude'],
                'types': row.get('types', []), 'status': None, 'address': row.get('formattedAddress'), 'maps_url': None}
    resolve.label = 'google'
    return resolve


OSM_TYPES = {('amenity', 'cafe'): 'cafe', ('amenity', 'restaurant'): 'restaurant', ('amenity', 'bar'): 'bar', ('amenity', 'pub'): 'bar',
             ('amenity', 'biergarten'): 'bar', ('amenity', 'nightclub'): 'night_club', ('amenity', 'fast_food'): 'meal_takeaway',
             ('amenity', 'ice_cream'): 'cafe', ('shop', 'bakery'): 'bakery', ('shop', 'coffee'): 'cafe', ('shop', 'wine'): 'bar',
             ('tourism', 'museum'): 'museum', ('tourism', 'gallery'): 'art_gallery', ('tourism', 'attraction'): 'tourist_attraction',
             ('tourism', 'viewpoint'): 'tourist_attraction', ('leisure', 'park'): 'park', ('leisure', 'garden'): 'park',
             ('natural', 'peak'): 'natural_feature', ('natural', 'hill'): 'natural_feature', ('amenity', 'place_of_worship'): 'church',
             ('landuse', 'cemetery'): 'historical_landmark', ('amenity', 'grave_yard'): 'historical_landmark',
             ('place', 'neighbourhood'): 'tourist_attraction', ('place', 'quarter'): 'tourist_attraction'}


def osm_resolver(*, fetch=None, user_agent='Trippy/1.0 (trip planner)'):
    """Free check on OpenStreetMap (Nominatim): position, kind, names, opening hours, website, phone.
    One request a second, cached for the process. Production at scale should point `fetch` at a
    self-hosted or paid Nominatim/Photon; the public server allows only light use."""
    import json, time, urllib.parse, urllib.request
    cache, last = {}, [0.0]

    def default_fetch(params):
        wait = 1.05 - (time.time() - last[0])
        if wait > 0: time.sleep(wait)
        last[0] = time.time()
        url = 'https://nominatim.openstreetmap.org/search?' + urllib.parse.urlencode(params)
        with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': user_agent}), timeout=20) as r:
            return json.load(r)

    get = fetch or default_fetch

    def resolve(query, destination, near):
        key = (query, destination, near)
        if key in cache: return cache[key]
        params = {'q': f'{query}, {destination}', 'format': 'jsonv2', 'limit': 1, 'namedetails': 1, 'extratags': 1}
        if near: params.update(viewbox=f'{near[1]-0.25},{near[0]+0.25},{near[1]+0.25},{near[0]-0.25}', bounded=1)
        try:
            rows = get(params)
            if not rows and ',' in query:   # the area Gemini named can be off; try the name alone
                rows = get(dict(params, q=f"{query.split(',')[0]}, {destination}"))
        except Exception:
            rows = []
        result = None
        if rows:
            r = rows[0]; names = r.get('namedetails') or {}; extra = r.get('extratags') or {}
            kind = 'historical_landmark' if r.get('category') == 'historic' else OSM_TYPES.get((r.get('category'), r.get('type')))
            result = {'id': f"osm-{(r.get('osm_type') or 'x')[:1]}{r.get('osm_id')}",
                      'name': names.get('name:en') or names.get('name') or r.get('name', ''),
                      'names': [v for k, v in names.items() if k == 'name' or k.startswith(('name:', 'alt_name', 'old_name'))],
                      'latitude': float(r['lat']), 'longitude': float(r['lon']), 'types': [kind] if kind else [],
                      'status': 'CLOSED_PERMANENTLY' if extra.get('disused') or extra.get('end_date') else None,
                      'address': r.get('display_name'), 'website': extra.get('website') or extra.get('contact:website'),
                      'phone': extra.get('phone') or extra.get('contact:phone'), 'opening_hours': extra.get('opening_hours'),
                      'maps_url': None}
        cache[key] = result
        return result
    resolve.label = 'openstreetmap'
    return resolve


def json_schema(schema):
    """Gemini's schema shape → strict JSON Schema for OpenAI-style models (GPT-6 Luna on Azure):
    lower-case types, every property required (optional ones may be empty strings), no extra keys."""
    kind = schema.get('type', 'STRING').lower()
    out = {'type': kind}
    if 'enum' in schema: out['enum'] = list(schema['enum'])
    if kind == 'object':
        props = {k: json_schema(v) for k, v in schema.get('properties', {}).items()}
        out.update(properties=props, required=list(props), additionalProperties=False)
    elif kind == 'array':
        out['items'] = json_schema(schema.get('items', {}))
    return out
