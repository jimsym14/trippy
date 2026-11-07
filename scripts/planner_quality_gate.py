#!/usr/bin/env python3
"""Offline quality gate for the personal_places Barcelona planner.

Runs fixed trip requests through the real pipeline against the local
catalog and video source pack, with no model, network or paid provider.
Automatic checks cover what code can judge (category suitability, walking
legs, grounding, reproducibility, theme coverage). Usefulness still needs a
human: the printed itinerary is meant to be scored with the 0-2 x 5 rubric
in docs/PRODUCT_EVALUATION_AND_REMAINING_STAGES.md. No score is invented here.

    .venv/bin/python scripts/planner_quality_gate.py [--json out.json]
"""
import argparse
import json
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from trippy.planner.personal_pipeline import run  # noqa: E402

# Requests cover the supported personal_places inputs; dates are in the future.
CASES = [
    {'id': 'balanced-3d-first-visit', 'days': ('2026-12-10', '2026-12-12'), 'interests': ['attraction', 'food'],
     'text': 'First visit, couple, want Gaudí, tapas and a nice evening', 'themes': {'gaudi', 'tapas'}},
    {'id': 'relaxed-2d-couple', 'days': ('2026-12-10', '2026-12-11'), 'interests': ['attraction', 'food'],
     'pace': 'relaxed', 'text': 'Relaxed couple, seafood and the beach', 'themes': {'seafood', 'beach'}},
    {'id': 'stopover-1d', 'days': ('2026-12-10', '2026-12-10'), 'interests': ['attraction', 'food'],
     'text': '', 'themes': set()},
    {'id': 'greek-request-2d', 'days': ('2026-12-10', '2026-12-11'), 'interests': ['attraction', 'food'],
     'text': 'Θέλω Γκαουντί, αγορά και τάπας', 'themes': {'gaudi', 'market', 'tapas'}},
    {'id': 'gracia-2d', 'days': ('2026-12-10', '2026-12-11'), 'interests': ['attraction', 'food'],
     'text': 'Focus on Gràcia: food and sights', 'themes': set(), 'area': 'Gràcia',
     # Known data gap: the video pack has few Gràcia venues (Park Güell only), so
     # an area-limited plan is mostly catalog inventory. Raise when coverage grows.
     'min_video_share': 0.1},
    {'id': 'no-video-evidence-3d', 'days': ('2026-12-10', '2026-12-12'), 'interests': ['attraction', 'food'],
     'text': 'First visit, want Gaudí and tapas', 'themes': {'gaudi', 'tapas'},
     # Simulates a city without creator videos: only Overture + Wikidata + Wikivoyage.
     'disable_videos': True, 'min_video_share': 0.0},
    {'id': 'seven-days', 'days': ('2026-12-10', '2026-12-16'), 'interests': ['attraction', 'food'],
     'text': 'Museums, art and good local food', 'themes': {'art'}, 'min_video_share': 0.2},
    # Seven days now hold quick in-between stops (squares, fountains, churches), so the
    # same 7 creator-video places are a smaller share of a longer plan (2026-11-07).
]
UNSUITABLE = {'movie_theater', 'drive_in_theater', 'theatre_venue', 'fast_food_restaurant', 'petting_zoo',
              'dog_park', 'skate_park', 'home_theater_systems_stores'}
MAX_LEG_MINUTES = 45          # draft walking estimate, not a verified route
MIN_EVIDENCE_SHARE = 0.5      # stops backed by a creator video, Wikivoyage or Wikidata fame
MIN_VIDEO_SHARE = 0.25        # Barcelona has creator videos; other cities may not


def brief(case):
    b = {'destination': 'Barcelona', 'planning_strategy': 'personal_places', 'travelers': {'count': 2},
         'date_range': {'arrival': case['days'][0], 'departure': case['days'][1]},
         'interests': case['interests'], 'custom_instructions': case['text']}
    if case.get('pace'):
        b['pace'] = case['pace']
    return b


def plan(case):
    from trippy.planner import endorsements
    original = endorsements.load
    if case.get('disable_videos'):
        endorsements.load = lambda root, city='Barcelona': {'entities': {}, 'core': None}
    try:
        with tempfile.TemporaryDirectory() as directory:
            return run(brief(case), directory=directory, root=ROOT)
    finally:
        endorsements.load = original


def categories_by_entity():
    import sqlite3
    with sqlite3.connect((ROOT / '.local/catalog.sqlite').resolve().as_uri() + '?mode=ro', uri=True) as db:
        return dict(db.execute('SELECT entity_id, source_category FROM catalog_snapshots'))


def evaluate(case, result, again, source_categories):
    places = {p['id']: p for p in result['places']}
    stops = [(d['date'], s) for d in result['itinerary']['days'] for s in d['stops']]
    checks, failures = {}, []
    signature = lambda r: [(d['date'], [(s['time'], s['place_id']) for s in d['stops']]) for d in r['itinerary']['days']]
    checks['reproducible'] = signature(result) == signature(again)
    checks['all_days_have_stops'] = all(d['stops'] for d in result['itinerary']['days'])
    bad = [places[s['place_id']]['name'] for _, s in stops
           if source_categories.get(s['place_id']) in UNSUITABLE]
    checks['no_unsuitable_categories'] = not bad
    legs = [s['travel_time_minutes'] for _, s in stops if s.get('travel_time_minutes') is not None]
    checks['max_leg_minutes'] = max(legs, default=0)
    checks['legs_within_limit'] = checks['max_leg_minutes'] <= MAX_LEG_MINUTES
    grounded = all(places[s['place_id']]['coordinates']['source_ids'] and places[s['place_id']]['source_ids']
                   for _, s in stops)
    checks['grounded'] = grounded
    def backed(tags):
        return 'source_recommended' in tags or 'wikivoyage_listed' in tags or any(t.startswith('notable:') for t in tags)
    endorsed = sum('source_recommended' in places[s['place_id']]['tags'] for _, s in stops)
    evidenced = sum(backed(places[s['place_id']]['tags']) for _, s in stops)
    checks['video_share'] = round(endorsed / len(stops), 2) if stops else 0
    checks['evidence_share'] = round(evidenced / len(stops), 2) if stops else 0
    checks['evidence_share_ok'] = checks['evidence_share'] >= MIN_EVIDENCE_SHARE
    checks['video_share_ok'] = checks['video_share'] >= case.get('min_video_share', MIN_VIDEO_SHARE)
    found = {t.split(':', 1)[1] for _, s in stops for t in places[s['place_id']]['tags'] if t.startswith('theme:')}
    checks['themes_missing'] = sorted(case['themes'] - found)
    checks['themes_covered'] = not checks['themes_missing']
    checks['unknown_prices_stay_unknown'] = all(p['price']['basis'] == 'unknown' for p in result['places'])
    checks['routes_unverified'] = all(not r.get('verified') for r in result.get('route_previews', []))
    if case.get('area'):
        from trippy.catalog.boundaries import AreaIndex
        index = AreaIndex.load(ROOT, 'Barcelona')
        if index is None:
            checks['area_boundaries_available'] = False
            failures.append('area_boundaries_available')
        else:
            areas = index.resolve(case['area'])
            outside = [places[s['place_id']]['name'] for _, s in stops if not AreaIndex.contains(
                areas, places[s['place_id']]['coordinates']['latitude'], places[s['place_id']]['coordinates']['longitude'])]
            checks['stops_outside_area'] = outside
            if outside:
                failures.append('stops_inside_area')
    for name in ['reproducible', 'all_days_have_stops', 'no_unsuitable_categories', 'legs_within_limit',
                 'grounded', 'evidence_share_ok', 'video_share_ok', 'themes_covered', 'unknown_prices_stay_unknown',
                 'routes_unverified']:
        if not checks[name]:
            failures.append(name)
    if bad:
        checks['unsuitable_stops'] = bad
    return checks, failures


def render(case, result):
    places = {p['id']: p for p in result['places']}
    lines = [f"## {case['id']}  ({case['text'] or 'no free text'})"]
    for day in result['itinerary']['days']:
        lines.append(f"Day {day['day']} {day['date']}")
        for s in day['stops']:
            p = places[s['place_id']]
            mark = '*' if 'source_recommended' in p['tags'] else ('w' if 'wikivoyage_listed' in p['tags'] else ('n' if any(t.startswith('notable:') for t in p['tags']) else ' '))
            walk = f"{s['travel_time_minutes']} min" if s.get('travel_time_minutes') is not None else 'start'
            lines.append(f"  {mark} {s['time']} {p['category']:<10} {p['name']}  [{walk}]  {p.get('address') or ''}")
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--json', type=Path, help='write machine-readable results here')
    args = parser.parse_args()
    if not (ROOT / '.local/catalog.sqlite').is_file():
        print('Local catalog missing: .local/catalog.sqlite', file=sys.stderr)
        return 2
    source_categories = categories_by_entity()
    report, failed = [], 0
    for case in CASES:
        result, again = plan(case), plan(case)
        checks, failures = evaluate(case, result, again, source_categories)
        failed += bool(failures)
        print(render(case, result))
        print(f"  checks: {json.dumps(checks, ensure_ascii=False)}")
        print(f"  {'PASS' if not failures else 'FAIL: ' + ', '.join(failures)}\n")
        report.append({'case': case['id'], 'checks': checks, 'failures': failures,
                       'pipeline_report': {k: result['pipeline_report'].get(k) for k in
                                           ('intent_extraction_path', 'scheduled_stops', 'place_provider')}})
    print(f"{len(CASES) - failed}/{len(CASES)} cases pass the automatic checks. "
          "* = creator video, w = Wikivoyage, n = notable on Wikidata. Human rubric scoring is still required.")
    print('Evidence = creator video, Wikivoyage listing or Wikidata fame (notable:N tag).')
    if args.json:
        args.json.write_text(json.dumps(report, ensure_ascii=False, indent=1))
    return 1 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
