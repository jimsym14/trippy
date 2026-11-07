"""Free fallback places from OpenStreetMap when the paid provider fails.

When Google's daily quota runs out mid-plan (it did for a Rome trip on
2026-11-07: bars came back, then clubs, cafés and restaurants all failed), a plan
with no lunch, dinner or coffee is worse than one with plain OSM venues. This
provider answers the same discovery task from one Overpass query around the
city centre (or the traveller's base) and ranks by what OSM can say about a
venue: a Wikidata/Wikipedia entry, a website, listed hours, a cuisine. No
ratings exist here, so the plan says these came from OpenStreetMap.

Geocoding (the city centre, a "Staying in Trastevere" note) uses Nominatim at
one request a second, cached on disk.
"""
from __future__ import annotations

import json
import math
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from .planning_contract import empty_batch

AGENT = {'User-Agent': 'Trippy/1.0 (travel planner)'}
OVERPASS = ('https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter')
FILTERS = {
    'food': ['["amenity"="restaurant"]'],
    'coffee': ['["amenity"="cafe"]'],
    'bar': ['["amenity"="bar"]', '["amenity"="pub"]'],
    'club': ['["amenity"="nightclub"]'],
}
RADIUS = {'food': 1800, 'coffee': 1500, 'bar': 2000, 'club': 3500}
CHAINS = ('mcdonald', 'burger king', 'starbucks', 'kfc', 'subway', 'domino', 'costa coffee', 'pizza hut', 'tim hortons')
_last_nominatim = [0.0]


def _metres(a_lat, a_lon, b_lat, b_lon):
    dy = (a_lat - b_lat) * 111_320
    dx = (a_lon - b_lon) * 111_320 * math.cos(math.radians(a_lat))
    return math.hypot(dx, dy)


def geocode(root, query, *, fetch=None):
    """(latitude, longitude) for a place name, or None. Cached forever per query."""
    cache_file = Path(root) / '.local/geocode.json'
    try: cache = json.loads(cache_file.read_text())
    except (OSError, ValueError): cache = {}
    key = ' '.join(query.casefold().split())
    if key in cache: return tuple(cache[key]) if cache[key] else None
    try:
        found = (fetch or _nominatim)(query)
    except Exception:  # noqa: BLE001 - optional lookup
        return None
    cache[key] = list(found) if found else None
    try:
        cache_file.parent.mkdir(parents=True, exist_ok=True); cache_file.write_text(json.dumps(cache, ensure_ascii=False))
    except OSError:
        pass
    return found


def _nominatim(query):
    wait = 1.1 - (time.time() - _last_nominatim[0])
    if wait > 0: time.sleep(wait)
    _last_nominatim[0] = time.time()
    from trippy import usage
    usage.hit('free:nominatim')
    url = 'https://nominatim.openstreetmap.org/search?' + urllib.parse.urlencode({'q': query, 'format': 'jsonv2', 'limit': 1})
    with urllib.request.urlopen(urllib.request.Request(url, headers=AGENT), timeout=10) as response:
        rows = json.load(response)
    return (float(rows[0]['lat']), float(rows[0]['lon'])) if rows else None


def stay_from_text(text):
    """"Staying in Trastevere" / "Stay: El Born" / "μένουμε στο Κουκάκι" → "Trastevere"."""
    import re
    match = re.search(r"(?:staying (?:in|at|near)|stay(?:ing)?:|hotel (?:in|at)|μένουμε (?:στο|στη|στην|στα)|διαμονή:?)\s+([^.,;\n]{2,60})",
                      text or '', re.IGNORECASE)
    return match.group(1).strip() if match else None


def overpass(query, *, timeout=100, mirrors=2):
    body = urllib.parse.urlencode({'data': query}).encode()
    error = None
    from trippy import usage
    usage.hit('free:overpass')
    for endpoint in OVERPASS[:mirrors]:
        try:
            request = urllib.request.Request(endpoint, data=body, headers=AGENT)
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.load(response).get('elements', [])
        except Exception as exc:  # noqa: BLE001 - try the mirror
            error = exc
    raise error or RuntimeError('overpass_unavailable')


class OsmTravelProvider:
    """Same `discover(task, brief)` contract as the Google provider."""
    name = 'openstreetmap'

    def __init__(self, root, *, fetch=overpass, locate=None):
        self.root, self.fetch = root, fetch
        self.locate = locate or (lambda query: geocode(root, query))
        self._elements = {}

    def elements(self, lat, lon):
        """Every category in ONE Overpass query per centre (its servers rate-limit bursts)."""
        key = (round(lat, 3), round(lon, 3))
        if key not in self._elements:
            parts = ''.join(f'nwr{f}["name"](around:{RADIUS[c]},{lat},{lon});' for c, fs in FILTERS.items() for f in fs)
            self._elements[key] = self.fetch(f'[out:json][timeout:90];({parts});out center tags 900;')
        return self._elements[key]

    def center(self, brief):
        base = brief.get('base') or {}
        if base.get('latitude') is not None: return base['latitude'], base['longitude']
        return self.locate(brief['destination'])

    def discover(self, task, brief):
        category = task['category']
        if category not in FILTERS: return empty_batch()
        center = self.center(brief)
        if not center: raise RuntimeError('destination_not_found')
        lat, lon = center
        wanted = {f[2:-2].replace('"="', '=') for f in FILTERS[category]}
        ranked = []
        for e in self.elements(lat, lon):
            tags = e.get('tags') or {}
            if f"amenity={tags.get('amenity')}" not in wanted: continue
            name = tags.get('name')
            plat = e.get('lat', (e.get('center') or {}).get('lat'))
            plon = e.get('lon', (e.get('center') or {}).get('lon'))
            if not name or plat is None or plon is None: continue
            if any(c in name.casefold() for c in CHAINS) or tags.get('brand:wikidata'): continue
            score = (30 if tags.get('wikidata') or tags.get('wikipedia') else 0) + (10 if tags.get('website') or tags.get('contact:website') else 0) \
                + (5 if tags.get('opening_hours') else 0) + (3 if tags.get('cuisine') else 0) - _metres(lat, lon, plat, plon) / 100
            ranked.append((score, e['type'], e['id'], name, plat, plon, tags))
        ranked.sort(key=lambda r: (-r[0], r[2]))
        batch = empty_batch(); checked = datetime.now(timezone.utc).isoformat()
        for score, kind, identifier, name, plat, plon, tags in ranked[:max(task.get('target', 12), 12)]:
            sid = f'osm-{kind}-{identifier}'
            batch['sources'].append({'id': sid, 'url': f'https://www.openstreetmap.org/{kind}/{identifier}',
                                     'publisher': 'OpenStreetMap', 'type': 'maps', 'checked_at': checked})
            street = ' '.join(x for x in (tags.get('addr:street'), tags.get('addr:housenumber')) if x)
            batch['places'].append({'id': sid, 'name': name, 'category': category, 'description': '',
                'why_recommended': '', 'address': street or None,
                'official_url': tags.get('website') or tags.get('contact:website'), 'source_ids': [sid],
                'coordinates': {'latitude': plat, 'longitude': plon, 'source_ids': [sid]},
                'identity_status': 'source_matched', 'tags': ['osm_fallback'] + ([f"cuisine:{tags['cuisine'].split(';')[0]}"] if tags.get('cuisine') else []),
                'price': {'min': None, 'max': None, 'currency': None, 'basis': 'unknown'}, 'price_source_ids': [],
                'cuisine': (tags.get('cuisine') or '').split(';')[0] or None, 'dietary_options': [], 'best_for': [],
                'best_time': None, 'reservation_required': None,
                'image_url': None, 'image_source_url': None, 'image_attribution': None,
                'rating': {'value': None, 'scale': None, 'platform': None, 'review_count': None},
                'average_visit_minutes': None, 'duration_basis': 'unknown'})
        return batch


class WikivoyageTravelProvider:
    """Eat and drink listings from the city's Wikivoyage guide (free, cached, fast).

    Each listing carries a human-written line ("Excellent traditional Roman
    restaurant..."), which the app shows as the reason, so no model is needed.
    """
    name = 'wikivoyage'
    COFFEE = ('caf', 'coffee', 'espresso', 'bakery', 'pastic', 'pâtiss', 'gelat', 'tea room', 'tearoom', 'teahouse', 'teaház', 'bar-caf', 'kávéház', 'kawiarnia', 'kafeneio')
    CLUB = ('club', 'disco', 'techno', 'dance', 'dj ')

    def __init__(self, root, *, listings=None, locate=None):
        self.root = root
        self.listings = listings
        self.locate = locate or (lambda query: geocode(root, query))

    LOCAL = ('traditional', 'typical', 'local', 'classic', 'family-run', 'home-made', 'homemade', 'authentic', 'best')
    ELSEWHERE = ('chinese', 'indian', 'thai', 'sushi', 'japanese', 'mexican', 'kebab', 'burger', 'american', 'irish')

    def local(self, listing):
        """A first visit wants the city's own food: "traditional Roman" before "Chinese"."""
        words = (listing.get('content') or '').casefold()
        return sum(w in words for w in self.LOCAL) - 2 * any(w in words for w in self.ELSEWHERE)

    def kind(self, listing):
        """One category per listing, so a café-bar is not offered as lunch, coffee and a club."""
        name = (listing.get('name') or '').casefold()
        words = f"{name} {(listing.get('content') or '')[:90].casefold()}"
        if listing.get('type') not in {'eat', 'drink'}: return None
        if any(w in words for w in self.CLUB) and listing['type'] == 'drink': return 'club'
        if any(w in name for w in self.COFFEE) or any(w in words[:len(name) + 40] for w in self.COFFEE): return 'coffee'
        return 'food' if listing['type'] == 'eat' else 'bar'

    def discover(self, task, brief):
        from .plan_notes import guide_listings
        from hashlib import sha256
        category = task['category']
        listings = self.listings if self.listings is not None else guide_listings(self.root, brief['destination'])
        base = brief.get('base') or {}
        # The centre is the base, else the middle of the guide's own sights (a city
        # geocode can land on a county centroid, as Budapest's does).
        sights = sorted((l['latitude'], l['longitude']) for l in listings if l.get('type') == 'see' and l.get('latitude') is not None)
        center = ((base['latitude'], base['longitude']) if base.get('latitude') is not None
                  else (sights[len(sights) // 2][0], sorted(p[1] for p in sights)[len(sights) // 2]) if sights
                  else self.locate(brief['destination']))
        rows = [l for l in listings if l.get('latitude') is not None and l.get('longitude') is not None and self.kind(l) == category]
        if center:
            rows = [l for l in rows if _metres(center[0], center[1], l['latitude'], l['longitude']) < 4500]
            rows.sort(key=lambda l: (_metres(center[0], center[1], l['latitude'], l['longitude']) // 700, -self.local(l), -len(l.get('content') or ''), l['name']))
        batch = empty_batch(); checked = datetime.now(timezone.utc).isoformat()
        seen = set()
        for l in rows[:max(task.get('target', 12), 12)]:
            if l['name'] in seen: continue
            seen.add(l['name'])
            url = 'https://en.wikivoyage.org/wiki/' + (l.get('page') or brief['destination']).replace(' ', '_')
            sid = 'wikivoyage-' + sha256(url.encode()).hexdigest()[:16]
            if sid not in {s['id'] for s in batch['sources']}:
                batch['sources'].append({'id': sid, 'url': url, 'publisher': 'Wikivoyage', 'type': 'guide', 'checked_at': checked})
            pid = 'wv-' + sha256(f"{l['name']}|{l['latitude']:.5f}|{l['longitude']:.5f}".encode()).hexdigest()[:20]
            batch['places'].append({'id': pid, 'name': l['name'], 'category': category,
                'description': (l.get('content') or '')[:600], 'why_recommended': (l.get('content') or '').split('. ')[0][:160],
                'address': None, 'official_url': None, 'source_ids': [sid],
                'coordinates': {'latitude': l['latitude'], 'longitude': l['longitude'], 'source_ids': [sid]},
                'identity_status': 'source_matched', 'tags': ['wikivoyage_listed'],
                'price': {'min': None, 'max': None, 'currency': None, 'basis': 'unknown'}, 'price_source_ids': [],
                'cuisine': None, 'dietary_options': [], 'best_for': [], 'best_time': None, 'reservation_required': None,
                'image_url': None, 'image_source_url': None, 'image_attribution': None,
                'rating': {'value': None, 'scale': None, 'platform': None, 'review_count': None},
                'average_visit_minutes': None, 'duration_basis': 'unknown'})
        return batch


class FallbackChain:
    """Wikivoyage first (fast, described); OpenStreetMap when the guide has too few."""
    name = 'wikivoyage+openstreetmap'

    def __init__(self, root, *, osm_fetch=None):
        self.providers = (WikivoyageTravelProvider(root),
                          OsmTravelProvider(root, fetch=osm_fetch or (lambda q: overpass(q, timeout=60, mirrors=1))))
        self.broken = set()

    def discover(self, task, brief):
        batch, error = empty_batch(), None
        for provider in self.providers:
            # A source that failed once in this plan (Overpass under load) is not retried.
            if provider.name in self.broken: continue
            try:
                found = provider.discover(task, brief)
            except Exception as exc:  # noqa: BLE001 - next source
                error = exc; self.broken.add(provider.name); continue
            names = {p['name'].casefold() for p in batch['places']}
            batch['sources'] += [s for s in found['sources'] if s['id'] not in {x['id'] for x in batch['sources']}]
            batch['places'] += [p for p in found['places'] if p['name'].casefold() not in names]
            if len(batch['places']) >= min(6, task.get('target', 6)): break
        if not batch['places'] and error: raise error
        return batch
