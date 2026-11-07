"""Famous places for any city, free, from Wikidata.

A single Google Text Search per category returns at most 20 places and misses
much of what a first visit to a capital is about (for Rome: the Forum, Piazza
Navona, Castel Sant'Angelo). Wikidata ranks places by how many Wikipedia
language editions cover them ("sitelinks"), a good proxy for "must-see". This
adds the well-known, visitable ones the provider didn't return, and marks the
ones it did return with their fame so the planner can weigh them.
"""
from __future__ import annotations

import json
import math
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from trippy.catalog.boundaries import city_slug

MIN_SITELINKS = 20
RADIUS_KM = 7
MAX_NEW = 25
CACHE_DAYS = 30
SKIP = {  # settlements, districts, institutions, events, transport, people's organisations
    'Q515', 'Q1549591', 'Q5119', 'Q1637706', 'Q15284', 'Q2074737', 'Q484170', 'Q747074', 'Q262166', 'Q1093829',
    'Q3918', 'Q875538', 'Q902104', 'Q38058796', 'Q3624078', 'Q6256', 'Q43229', 'Q4830453', 'Q178706', 'Q1656682',
    'Q131569', 'Q4022', 'Q35657', 'Q107390', 'Q532', 'Q486972', 'Q7930989', 'Q1248784', 'Q55488', 'Q928830',
    'Q11032', 'Q1907114', 'Q16917', 'Q7075', 'Q22806', 'Q2085381',
}
MUSEUMS = {'Q33506', 'Q207694', 'Q16735822', 'Q3329412', 'Q588140', 'Q1007870', 'Q2668072', 'Q1970365', 'Q17431399', 'Q2772772'}
NATURE = {'Q22698', 'Q22746', 'Q1107656', 'Q167346', 'Q6017969', 'Q54050', 'Q40080', 'Q8502', 'Q46169'}
VISITABLE = {'Q16970', 'Q163687', 'Q174782', 'Q483453', 'Q16560', 'Q23413', 'Q4989906', 'Q839954', 'Q641226', 'Q12280',
             'Q570116', 'Q44539', 'Q2977', 'Q12518', 'Q57821', 'Q1081138', 'Q24398318', 'Q162875', 'Q15243209', 'Q1440300'}


def fold(value):
    import unicodedata
    text = unicodedata.normalize('NFKD', value or '').encode('ascii', 'ignore').decode().casefold()
    return ''.join(ch for ch in text if ch.isalnum())


def metres(a_lat, a_lon, b_lat, b_lon):
    dy = (a_lat - b_lat) * 111_320
    dx = (a_lon - b_lon) * 111_320 * math.cos(math.radians(a_lat))
    return math.hypot(dx, dy)


def query_wikidata(latitude, longitude):
    query = f"""
    SELECT ?item ?itemLabel ?loc ?links (GROUP_CONCAT(DISTINCT ?t) AS ?types) (COUNT(?built) AS ?builtSignals) WHERE {{
      SERVICE wikibase:around {{ ?item wdt:P625 ?loc . bd:serviceParam wikibase:center "Point({longitude} {latitude})"^^geo:wktLiteral .
                                bd:serviceParam wikibase:radius "{RADIUS_KM}" . }}
      ?item wikibase:sitelinks ?links . FILTER(?links > {MIN_SITELINKS})
      OPTIONAL {{ ?item wdt:P31 ?t }}
      OPTIONAL {{ ?item wdt:P1435|wdt:P84|wdt:P149 ?built }}
      SERVICE wikibase:label {{ bd:serviceParam wikibase:language "en". }}
    }} GROUP BY ?item ?itemLabel ?loc ?links ORDER BY DESC(?links) LIMIT 90"""
    url = 'https://query.wikidata.org/sparql?' + urllib.parse.urlencode({'query': query})
    request = urllib.request.Request(url, headers={'Accept': 'application/sparql-results+json',
                                                   'User-Agent': 'Trippy/1.0 (travel planner)'})
    with urllib.request.urlopen(request, timeout=25) as response:
        rows = json.load(response)['results']['bindings']
    items = []
    for row in rows:
        value = lambda k: (row.get(k) or {}).get('value')
        name, loc, qid = value('itemLabel'), value('loc'), (value('item') or '').rsplit('/', 1)[-1]
        if not name or not loc or (name.startswith('Q') and name[1:].isdigit()): continue
        types = {t.rsplit('/', 1)[-1] for t in (value('types') or '').split()}
        if types & SKIP: continue
        built = int(value('builtSignals') or 0)
        if not built and not types & (VISITABLE | MUSEUMS | NATURE): continue
        lon, lat = (float(x) for x in loc.replace('Point(', '').replace(')', '').split())
        category = 'museum' if types & MUSEUMS else 'nature' if types & NATURE else 'attraction'
        items.append({'qid': qid, 'name': name, 'latitude': lat, 'longitude': lon,
                      'sitelinks': int(value('links') or 0), 'category': category})
    return items


def famous_items(root, destination, latitude, longitude, *, fetch=query_wikidata, log=lambda *a: None):
    cache = Path(root) / '.local/famous' / f'{city_slug(destination)}.json'
    try:
        if cache.is_file() and time.time() - cache.stat().st_mtime < CACHE_DAYS * 86400:
            return json.loads(cache.read_text())
    except (OSError, ValueError):
        pass
    try:
        items = fetch(latitude, longitude)
    except Exception as error:  # noqa: BLE001 - optional enrichment
        log('famous_failed', {'error': type(error).__name__})
        return []
    try:
        cache.parent.mkdir(parents=True, exist_ok=True); cache.write_text(json.dumps(items, ensure_ascii=False))
    except OSError:
        pass
    return items


def enrich(batches, items, categories):
    """Tag provider places with their fame and return a batch of the famous ones they missed."""
    existing = [p for b in batches for p in b['places'] if p['coordinates'].get('latitude') is not None]
    places, sources = [], []
    def too_close(item):
        # Two items this close are one stop for a visitor (Piazza di Spagna / Spanish Steps).
        return any(metres(item['latitude'], item['longitude'], p['coordinates']['latitude'], p['coordinates']['longitude']) < 130
                   for p in existing + places)
    checked = datetime.now(timezone.utc).isoformat()
    for item in items:
        key = fold(item['name'])
        match = next((p for p in existing if metres(item['latitude'], item['longitude'], p['coordinates']['latitude'],
                                                     p['coordinates']['longitude']) < 300
                      and len(key) >= 4 and (key in fold(p['name']) or fold(p['name']) in key)), None)
        tag = f"notable:{item['sitelinks']}"
        if match:
            if tag not in match['tags']: match['tags'] = sorted(set(match['tags'] + [tag]))
            continue
        if item['category'] not in categories or len(places) >= MAX_NEW or too_close(item): continue
        sid = 'wikidata-' + item['qid']
        sources.append({'id': sid, 'url': 'https://www.wikidata.org/wiki/' + item['qid'], 'publisher': 'Wikidata',
                        'type': 'reference', 'checked_at': checked})
        places.append({'id': 'wd-' + item['qid'], 'name': item['name'], 'category': item['category'],
            'description': '', 'why_recommended': '', 'address': None, 'official_url': None, 'source_ids': [sid],
            'coordinates': {'latitude': item['latitude'], 'longitude': item['longitude'], 'source_ids': [sid]},
            'identity_status': 'source_matched', 'tags': [tag, 'wikidata_famous'],
            'price': {'min': None, 'max': None, 'currency': None, 'basis': 'unknown'}, 'price_source_ids': [],
            'cuisine': None, 'dietary_options': [], 'best_for': [], 'best_time': None, 'reservation_required': None,
            'image_url': None, 'image_source_url': None, 'image_attribution': None,
            'rating': {'value': None, 'scale': None, 'platform': None, 'review_count': None},
            'average_visit_minutes': None, 'duration_basis': 'unknown'})
    return {'sources': sources, 'places': places, 'date_checks': [], 'constraint_checks': [], 'calendar_checks': [],
            'ticket_options': [], 'transport_options': [], 'events': [], 'seasonal_notes': [], 'gaps': []}
