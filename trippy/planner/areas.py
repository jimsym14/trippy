"""Plan a trip area by area, from the traveller's base.

A good city trip covers the important areas and spends each day in one or two
neighbouring ones, instead of crossing the city for each "best" place. This
module is pure and deterministic:

* `cluster` groups visitable places into walkable areas (~1 km across);
* `importance` ranks areas by their strongest places (fame, quality, saved pins);
* `assign` gives each day one main area (plus a close neighbour when the main
  one is small), most important areas first, the base's own area on the
  arrival day, and the area nearest the base on the departure day;
* the engine then prefers places inside the day's areas.

Area names are added later by the pipeline (a network lookup), never here.
"""
from __future__ import annotations

import math

VISIT = {'attraction', 'museum', 'nature', 'excursion', 'shopping'}
JOIN_METRES = 850       # a place joins an area whose centre is this close
MERGE_METRES = 1400     # a lone place merges into an area this close
PAIR_METRES = 2200      # a small area shares a day with a neighbour this close
DAY_RADIUS = 1300       # "in the day's area": within this of one of its centres


def metres(a, b):
    dy = (a[0] - b[0]) * 111_320
    dx = (a[1] - b[1]) * 111_320 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)


def point(place):
    c = place['coordinates']
    return (c['latitude'], c['longitude'])


def fame(place):
    return max([int(t.split(':', 1)[1]) for t in place.get('tags', []) if t.startswith('notable:') and t.split(':', 1)[1].isdigit()] or [0])


def strength(place):
    """How much a place should pull a day towards its area (not a rating)."""
    # Fame (Wikipedia editions) leads; catalog quality only counts above a baseline,
    # so many fair places don't outweigh a few great ones.
    score = 0.0
    for tag in place.get('tags', []):
        if tag.startswith('quality:') and tag[8:].isdigit(): score += max(0, int(tag[8:]) - 60) * 0.6
    score += min(fame(place), 150) * 0.8
    rating = place.get('rating') or {}
    if rating.get('value') and rating.get('review_count'):
        score += (rating['value'] - 4.0) * 12 * min(1.0, math.log10(max(rating['review_count'], 1)) / 3)
    return score + 120 * place.get('personal_priority', 0) / 100


def cluster(places, wanted_tags=()):
    """Greedy, strongest first: deterministic for the same inputs.

    Places matching what the traveller asked for (preference tags such as
    "beach" or "art") count extra, so their areas get a day.
    """
    wanted = set(wanted_tags)
    # Catalog places carry "theme:x" only for themes the traveller asked for.
    asked = {p['id'] for p in places if wanted & set(p.get('tags', [])) or any(t.startswith('theme:') for t in p.get('tags', []))}
    def weight(p): return strength(p) + (60 if p['id'] in asked else 0)
    visits = sorted((p for p in places if p['category'] in VISIT), key=lambda p: (-weight(p), p['id']))
    areas = []
    for place in visits:
        here = point(place)
        nearest = min(areas, key=lambda a: metres(a['center'], here), default=None)
        if nearest and metres(nearest['center'], here) < JOIN_METRES:
            nearest['members'].append(place)
            pts = [point(p) for p in nearest['members']]
            nearest['center'] = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
        else:
            areas.append({'center': here, 'members': [place]})
    # Lone places join a close area rather than becoming an "area" of one.
    singles = [a for a in areas if len(a['members']) == 1]
    for single in singles:
        others = [a for a in areas if a is not single and len(a['members']) > 1]
        nearest = min(others, key=lambda a: metres(a['center'], single['center']), default=None)
        if nearest and metres(nearest['center'], single['center']) < MERGE_METRES:
            nearest['members'] += single['members']; areas.remove(single)
    result = []
    for index, area in enumerate(sorted(areas, key=lambda a: (-importance(a['members'], weight), a['members'][0]['id']))):
        top = max(area['members'], key=lambda p: (strength(p), p['id']))
        result.append({'id': f'area-{index + 1}', 'latitude': round(area['center'][0], 6), 'longitude': round(area['center'][1], 6),
                       'place_ids': sorted(p['id'] for p in area['members']), 'importance': round(importance(area['members'], weight), 1),
                       'anchor_place_id': top['id'], 'anchor_name': top['name'], 'name': None})
    return result


def importance(members, weight=None):
    """The best place counts fully, the next ones less: two masterpieces beat five fair sights."""
    scores = sorted(((weight or strength)(p) for p in members), reverse=True)
    return sum(s * f for s, f in zip(scores, (1.0, 0.6, 0.35, 0.2))) + 2 * len(members)


def assign(areas, dates, *, base=None, partial_first=False, partial_last=False):
    """date -> [area ids]. Returns (by_date, uncovered area ids)."""
    if not dates or not areas: return {d: [] for d in dates}, [a['id'] for a in areas]
    by_id = {a['id']: a for a in areas}
    center = lambda a: (a['latitude'], a['longitude'])
    left = [a['id'] for a in sorted(areas, key=lambda a: -a['importance'])]
    plan = {d: [] for d in dates}
    base_point = (base['latitude'], base['longitude']) if base and base.get('latitude') is not None else None

    def take(area_id, date):
        plan[date].append(area_id); left.remove(area_id)

    def nearest_to(target, pool):
        return min(pool, key=lambda i: metres(center(by_id[i]), target), default=None)

    full = [d for i, d in enumerate(dates) if not (i == 0 and partial_first) and not (i == len(dates) - 1 and partial_last)]
    edges = ([dates[0]] if partial_first else []) + ([dates[-1]] if partial_last and len(dates) > 1 else [])
    # The most important areas go to full days; short first/last days then take what's
    # left closest to the base (or, without a base, the next most important).
    for date in full:
        if not left: break
        main = left[0]; take(main, date)
        # A neighbour shares the day when the main area is small, or when the neighbour
        # matters nearly as much (Sagrada Família and Passeig de Gràcia in one day).
        if left:
            # The most important neighbour within reach, not merely the nearest.
            near = [i for i in left if metres(center(by_id[main]), center(by_id[i])) < PAIR_METRES]
            friend = max(near, key=lambda i: by_id[i]['importance'], default=None)
            close = friend is not None
            if close and (len(by_id[main]['place_ids']) < 4 or by_id[friend]['importance'] >= 0.5 * by_id[main]['importance']):
                take(friend, date)
    for date in edges:
        if not left: break
        take(nearest_to(base_point, left) if base_point else left[0], date)
    # Left over areas that are close to a planned day ride along with it.
    for area_id in list(left):
        # Only full days have room for a third area; a short day keeps its one.
        best = min(((d, min(metres(center(by_id[area_id]), center(by_id[a])) for a in ids)) for d, ids in plan.items() if ids and d in full),
                   key=lambda x: x[1], default=None)
        # Only small areas ride along; an important one is better left for its own trip.
        if best and best[1] < 1200 and len(plan[best[0]]) < 3 and len(by_id[area_id]['place_ids']) <= 2: take(area_id, best[0])
    return plan, left


def outside_metres(place, centers):
    """How far a place lies beyond the day's areas (0 inside, or with no areas).

    The first centre is the day's main area: being only in a secondary area
    costs a little, so the main area's own sights come first.
    """
    if not centers: return 0
    beyond = max(0.0, min(metres(point(place), c) for c in centers) - DAY_RADIUS)
    if len(centers) > 1 and metres(point(place), centers[0]) > DAY_RADIUS: beyond += 500
    return beyond


def in_day_area(place, centers):
    return not centers or any(metres(point(place), c) < DAY_RADIUS for c in centers)
