"""Words for a finished plan, from one Gemini call.

The deterministic engine owns which stops happen and when. This pass only
writes: a title and one line per day, one reason and an optional tip per
stop, and a short trip summary. Everything goes in a single request whose
input and output are both bounded, so a 7-day plan costs one free-tier call:

* input: scheduled stops only (id, name, category, area) plus at most one
  short Wikivoyage line per stop, never the whole candidate pool;
* output: a fixed schema with word limits, trimmed again in code.

Wikivoyage (CC BY-SA) is fetched on demand for any destination, a few pages
at most, cached on disk. It gives local knowledge Google Places lacks.
Any failure leaves the plan exactly as the engine made it.
"""
from __future__ import annotations

import json
import re
import time
from hashlib import sha256
from pathlib import Path

from trippy.catalog.boundaries import area_key, city_slug

GUIDE_PAGES = 4               # main article + first district pages
GUIDE_MAX_AGE = 30 * 86400
MAX_STOPS = 40                # 7 days x ~5 stops; longer trips are annotated in part
LIMITS = {'title': 5, 'summary': 20, 'why': 18, 'tip': 16, 'trip': 40, 'character': 22, 'vibe': 4}
MAX_AREAS = 12

SYSTEM = """You write the short notes inside a travel app's itinerary. The stops, order and times are final:
never add, remove, rename or move a stop, and never invent opening hours, prices or facts.
Write in {language}. Be concrete and warm, no clichés ("hidden gem", "must-see", "vibrant").
- day title: 2-4 words naming that day's character (e.g. "Ancient Rome on foot").
- day summary: one sentence on how the day flows.
- why: one sentence on why this stop fits this traveller and this day.
- tip: one practical tip only when the guide line or common knowledge gives a real one; otherwise "".
- trip summary: two sentences for the whole trip.
- area: for each listed area, one sentence on its character for a visitor; a 2-4 word vibe;
  and 1-5 scores from general knowledge: touristy (5 = very), price (5 = expensive), safety
  (5 = very safe, also at night). Be honest and concrete; these are estimates, not facts.
Use the guide lines when given; they come from Wikivoyage."""

SCHEMA = {
    'type': 'OBJECT',
    'properties': {
        'trip_summary': {'type': 'STRING'},
        'days': {'type': 'ARRAY', 'items': {'type': 'OBJECT', 'properties': {
            'date': {'type': 'STRING'}, 'title': {'type': 'STRING'}, 'summary': {'type': 'STRING'}},
            'required': ['date', 'title', 'summary']}},
        'stops': {'type': 'ARRAY', 'items': {'type': 'OBJECT', 'properties': {
            'id': {'type': 'STRING'}, 'why': {'type': 'STRING'}, 'tip': {'type': 'STRING'}},
            'required': ['id', 'why', 'tip']}},
        'areas': {'type': 'ARRAY', 'items': {'type': 'OBJECT', 'properties': {
            'id': {'type': 'STRING'}, 'character': {'type': 'STRING'}, 'vibe': {'type': 'STRING'},
            'touristy': {'type': 'INTEGER'}, 'price': {'type': 'INTEGER'}, 'safety': {'type': 'INTEGER'}},
            'required': ['id', 'character', 'vibe', 'touristy', 'price', 'safety']}},
    },
    'required': ['trip_summary', 'days', 'stops', 'areas'],
}
LANGUAGES = {'el': 'Greek', 'en': 'English'}


# -- Wikivoyage on demand ----------------------------------------------------
def guide_listings(root, destination, *, fetcher=None, log=lambda *a: None):
    """Listings (see/do/eat/drink/buy) for a destination; [] when there is no article."""
    directory = Path(root) / '.local/city_layer' / city_slug(destination)
    cached = directory / 'guide.json'
    try:
        if cached.is_file() and time.time() - cached.stat().st_mtime < GUIDE_MAX_AGE:
            return json.loads(cached.read_text())['listings']
    except (OSError, ValueError, KeyError):
        pass
    from trippy.catalog.city_layer import Fetcher, collect_wikivoyage
    try:
        fetcher = fetcher or Fetcher(Path(root) / '.local/city_layer/http-cache', min_interval=1.0, max_attempts=2,
                                     log=lambda *a: None)
        data = collect_wikivoyage(fetcher, destination.strip().title(), max_pages=GUIDE_PAGES)
    except Exception as error:  # noqa: BLE001 - the guide is optional
        log('guide_failed', {'error': type(error).__name__})
        return []
    listings = [{k: l.get(k) for k in ('type', 'name', 'alt', 'latitude', 'longitude', 'content', 'page')}
                for page in data['pages'] for l in page['listings'] if l.get('content')]
    try:
        directory.mkdir(parents=True, exist_ok=True)
        cached.write_text(json.dumps({'destination': destination, 'licence': data['licence'],
                                      'pages': [p['url'] for p in data['pages']], 'listings': listings},
                                     ensure_ascii=False))
    except OSError:
        pass
    return listings


def _metres(a_lat, a_lon, b_lat, b_lon):
    import math
    dy = (a_lat - b_lat) * 111_320
    dx = (a_lon - b_lon) * 111_320 * math.cos(math.radians(a_lat))
    return math.hypot(dx, dy)


def match_guide(places, listings):
    """place id -> listing, by name (either way contained) or a listing within 120 m."""
    keyed = [(area_key(l['name'], keep_generic=True), area_key(l.get('alt') or '', keep_generic=True), l) for l in listings]
    found = {}
    for place in places:
        name = area_key(place.get('name', ''), keep_generic=True)
        coords = place.get('coordinates') or {}
        best = None
        for key, alt, listing in keyed:
            if len(name) >= 4 and any(k and len(k) >= 4 and (k == name or k in name or name in k) for k in (key, alt)):
                best = listing; break
            if best is None and listing.get('latitude') is not None and coords.get('latitude') is not None \
                    and _metres(coords['latitude'], coords['longitude'], listing['latitude'], listing['longitude']) < 120 \
                    and key and key.split()[0] in name:
                best = listing
        if best:
            found[place['id']] = best
    return found


# -- the one call ---------------------------------------------------------------
def _words(text, limit):
    words = str(text or '').split()
    clipped = ' '.join(words[:limit])
    return clipped if len(words) <= limit else clipped.rstrip(',;:') + '…'


def request_text(result, brief, guide):
    places = {p['id']: p for p in result['places']}
    lines = [f"Destination: {brief['destination']}",
             f"Travellers: {(brief.get('travelers') or {}).get('count', 2)} · pace: {brief.get('pace') or 'balanced'}"
             f" · interests: {', '.join(brief.get('interests') or []) or 'general'}"]
    if (brief.get('custom_instructions') or '').strip():
        lines.append('Request: ' + brief['custom_instructions'].strip()[:300])
    count = 0
    for day in result['itinerary']['days']:
        lines.append(f"\nDAY {day['date']}")
        for stop in day['stops']:
            if count >= MAX_STOPS:
                break
            place = places.get(stop['place_id'], {})
            area = (place.get('address') or '').split(',')[0][:60]
            own = ' · saved by the traveller' if place.get('personal_priority') else ''
            lines.append(f"- [{stop['place_id']}] {stop['time']} {place.get('name', stop['activity'])} ({place.get('category')}) {area}{own}")
            if stop['place_id'] in guide:
                lines.append(f"  guide: {guide[stop['place_id']]['content'][:220]}")
            count += 1
    base = (result.get('itinerary') or {}).get('base')
    if base: lines.insert(2, f"Base: {base.get('name')} (every day starts and ends here)")
    area_rows = (result.get('areas') or [])[:MAX_AREAS]
    if area_rows:
        names = {p['id']: p['name'] for p in result['places']}
        lines.append('\nAREAS')
        for area in area_rows:
            sample = ', '.join(names.get(i, '') for i in area['place_ids'][:4])
            when = ', '.join(area.get('days') or []) or 'not in this plan'
            lines.append(f"- [{area['id']}] {area.get('name')}: {sample} ({when})")
    return '\n'.join(lines)


def annotate(pool, result, brief, guide, *, cache_dir=None):
    """Write notes into the plan in place. Returns a small report; never raises."""
    days = result.get('itinerary', {}).get('days') or []
    if not days or not any(d['stops'] for d in days):
        return {'status': 'skipped', 'reason': 'no_stops'}
    language = LANGUAGES.get((brief.get('language') or 'el')[:2], 'Greek')
    text = request_text(result, brief, guide)
    key = sha256((language + text).encode()).hexdigest()[:24]
    cache = Path(cache_dir) / f'plan-notes-{key}.json' if cache_dir else None
    payload = model = None; called = False
    if cache and cache.is_file():
        try:
            stored = json.loads(cache.read_text()); payload, model = stored['notes'], stored['model']
        except (OSError, ValueError, KeyError):
            payload = None
    if payload is None:
        try:
            payload, model = pool.generate([{'text': text}], schema=SCHEMA, system=SYSTEM.format(language=language),
                                           temperature=0.5, thinking_budget=0)
        except Exception as error:  # noqa: BLE001 - notes are optional
            return {'status': 'failed', 'reason': type(error).__name__, 'retry_at': getattr(error, 'retry_at', None), 'calls': 1}
        called = True
        if cache:
            try: cache.parent.mkdir(parents=True, exist_ok=True); cache.write_text(json.dumps({'notes': payload, 'model': model}, ensure_ascii=False))
            except OSError: pass
    by_date = {d.get('date'): d for d in payload.get('days', []) if isinstance(d, dict)}
    by_stop = {s.get('id'): s for s in payload.get('stops', []) if isinstance(s, dict)}
    places = {p['id']: p for p in result['places']}
    written = 0
    for day in days:
        note = by_date.get(day['date'])
        if note and note.get('title', '').strip():
            day['theme'] = _words(note['title'], LIMITS['title'])
            day['summary'] = _words(note.get('summary'), LIMITS['summary'])
        for stop in day['stops']:
            note = by_stop.get(stop['place_id'])
            if not note or not note.get('why', '').strip():
                continue
            stop['why'] = _words(note['why'], LIMITS['why'])
            tip = _words(note.get('tip'), LIMITS['tip'])
            if tip:
                stop['tip'] = tip
            place = places.get(stop['place_id'])
            if place is not None:
                place['why_recommended'] = stop['why']
                if stop['place_id'] in guide and not place.get('description'):
                    place['description'] = guide[stop['place_id']]['content']
                    place['guide_page'] = guide[stop['place_id']].get('page')
            written += 1
    by_area = {a.get('id'): a for a in payload.get('areas', []) if isinstance(a, dict)}
    for area in result.get('areas') or []:
        note = by_area.get(area['id'])
        if not note or not str(note.get('character', '')).strip(): continue
        area['character'] = _words(note['character'], LIMITS['character'])
        area['vibe'] = _words(note.get('vibe'), LIMITS['vibe'])
        for field in ('touristy', 'price', 'safety'):
            value = note.get(field)
            if isinstance(value, (int, float)) and 1 <= value <= 5: area[field] = int(value)
        area['character_source'] = 'model_estimate'
    if payload.get('trip_summary', '').strip():
        result.setdefault('overview', {})['summary'] = _words(payload['trip_summary'], LIMITS['trip'])
    total = sum(len(d['stops']) for d in days)
    return {'status': 'written' if written else 'empty', 'model': model, 'stops_written': written,
            'stops_total': total, 'guide_matches': len(guide), 'calls': int(called)}
