"""The city's food and nightlife scene: what is worth it here, in words and places.

Some cities are their bars (Budapest's ruin bars, Kraków's cellar pubs), others
their tavernas or markets. A plan lists restaurants slot by slot; this section
says what the scene *is*, from the city guide's own Eat and Drink prose
(Wikivoyage, CC BY-SA, credited), and picks a few places to start with, each
with a reason taken from data, never from a model:

* a Wikivoyage listing's own line, when the guide covers the place;
* otherwise its Google rating and review count;
* a place the traveller saved first, with "Saved by you".
"""
from __future__ import annotations

import math

from .plan_notes import match_guide

PICKS = 6


def _score(place):
    rating = place.get('rating') or {}
    value, count = rating.get('value'), rating.get('review_count') or 0
    score = 200 * (place.get('personal_priority', 0) > 0)
    if value: score += (value - 3.5) * 20 * min(1.0, math.log10(max(count, 1)) / 3.5)
    if 'wikivoyage_listed' in place.get('tags', []): score += 8
    return score


def reason(place, guide_line=None):
    if place.get('personal_priority'): return 'Saved by you'
    if guide_line: return guide_line.split('. ')[0][:150]
    from .visits import fame
    known = fame(place)
    if place.get('category') in {'attraction', 'museum', 'nature'} and known >= 30:
        return ('A world-famous landmark' if known >= 100 else "One of the city's best-known sights" if known >= 60
                else 'A well-known sight')
    rating = place.get('rating') or {}
    if rating.get('value') and rating.get('review_count'):
        return f"{rating['value']:.1f}★ on Google from {rating['review_count']:,} reviews"
    if place.get('why_recommended') and place['why_recommended'] not in {'Επιλογή για το ταξίδι σου', 'Από τη βιβλιοθήκη σου'}:
        return place['why_recommended'][:150]
    return None


def build(result, listings, scene_text):
    """{'eat': {text, picks}, 'drink': {text, picks}, 'source_url'} or {} when there is nothing to say."""
    places = result.get('places') or []
    planned = {s['place_id'] for d in result.get('itinerary', {}).get('days', []) for s in d['stops']}
    out = {}
    for section, categories in (('eat', {'food'}), ('drink', {'bar', 'club'})):
        pool = [p for p in places if p.get('category') in categories and p['coordinates'].get('latitude') is not None]
        guide = match_guide(pool, listings or [])
        ranked = sorted(pool, key=lambda p: (-_score(p), p['name']))[:PICKS]
        picks = []
        for p in ranked:
            line = (guide.get(p['id']) or {}).get('content') if isinstance(guide.get(p['id']), dict) else guide.get(p['id'])
            picks.append({'place_id': p['id'], 'name': p['name'], 'category': p['category'],
                          'reason': reason(p, line), 'planned': p['id'] in planned})
        text = (scene_text or {}).get(section)
        if text or picks:
            out[section] = {'text': text, 'picks': picks}
    if out and (scene_text or {}).get('source_url'):
        out['source_url'] = scene_text['source_url']
        out['licence'] = 'CC BY-SA 4.0 (Wikivoyage)'
    return out


def add_reasons(result, listings):
    """Every place gets a short, data-backed `reason` the app can show without a model."""
    guide = match_guide(result.get('places') or [], listings or [])
    for place in result.get('places') or []:
        line = guide.get(place['id'])
        text = reason(place, line.get('content') if isinstance(line, dict) else None)
        if text: place['reason'] = text
        if isinstance(line, dict) and line.get('content') and not place.get('description'):
            place['description'] = line['content'][:600]
