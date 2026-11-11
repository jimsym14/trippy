#!/usr/bin/env python3
"""What a real plan costs and how good it is: the live path, measured.

Runs fixed trips through the real pipeline exactly as the server does with today's default settings (AI place
ideas, checked on OpenStreetMap, notes by Gemini), twice each: once cold and once again, to show what the
planner cache saves. Every model call and OpenStreetMap lookup is counted, and each plan is checked for the
things code can judge. Calls go to Gemini and OpenStreetMap; no Google Places call is made.

    .venv/bin/python scripts/planner_cost_quality.py [--only rome] [--json out.json] [--no-notes]

Prices are the paid-tier list prices in trippy/planner/planner_config.py (the free tier costs nothing).
Tokens are estimated from text length (4 characters a token), so costs are estimates, not a bill.
"""
import argparse
import json
import math
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from bridge_server import GeminiPool, community_videos, place_takes, read_environment  # noqa: E402
from trippy.planner.gemini_blend import GeminiBlendProvider, osm_resolver  # noqa: E402
from trippy.planner.osm_places import FallbackChain  # noqa: E402
from trippy.planner.personal_pipeline import run  # noqa: E402
from trippy.planner.place_cache import PlaceCache, cached_generate, cached_resolver  # noqa: E402
from trippy.planner.planner_config import MODELS  # noqa: E402
from trippy.planner.planning_contract import categories, normalized_brief  # noqa: E402
from trippy.social.community import plan_nodes  # noqa: E402

IDEA_MODEL = 'gemini-3.6-flash'
NOTES_MODEL = 'gemini-3.5-flash-lite'
CASES = [
    {'id': 'rome', 'destination': 'Rome', 'days': ('2027-03-12', '2027-03-14'), 'travelers': 2, 'interests': ['attraction', 'food', 'coffee'],
     'tags': ['local'], 'text': 'First time in Rome, staying in Trastevere. Good trattorias, not tourist traps.',
     'must': ['colosseum', 'pantheon', 'trevi', 'vatican']},
    {'id': 'athens', 'destination': 'Athens', 'days': ('2027-04-02', '2027-04-03'), 'travelers': 4, 'interests': ['attraction', 'food', 'nightlife'],
     'tags': [], 'text': 'Friends weekend, staying in Koukaki. Bars and good souvlaki.', 'must': ['acropolis|parthenon']},
    {'id': 'lisbon', 'destination': 'Lisbon', 'days': ('2027-05-06', '2027-05-09'), 'travelers': 3, 'interests': ['attraction', 'food', 'museum'],
     'tags': [], 'text': '', 'must': ['belem', 'jeronimos']},
    # The same engine with community videos feeding it (Barcelona has indexed YouTube videos).
    {'id': 'barcelona-videos', 'destination': 'Barcelona', 'days': ('2027-03-12', '2027-03-13'), 'travelers': 2, 'interests': ['attraction', 'food'],
     'tags': [], 'text': 'Gaudí and tapas, staying in El Born', 'must': ['sagrada'], 'videos': True},
]
MAX_LEG_MINUTES = 45


class Meter:
    """Counts what a run asked of the outside world."""
    def __init__(self):
        self.calls = {'ideas': 0, 'osm': 0, 'notes': 0}
        self.tokens = {'ideas': [0, 0], 'notes': [0, 0]}

    def snapshot(self):
        return {'calls': dict(self.calls), 'tokens': {k: list(v) for k, v in self.tokens.items()}}

    def usd(self, since):
        def cost(kind, model):
            spec = MODELS[model]
            tin = self.tokens[kind][0] - since['tokens'][kind][0]
            tout = self.tokens[kind][1] - since['tokens'][kind][1]
            calls = self.calls[kind] - since['calls'][kind]
            return (tin * spec['in'] + (tout + calls * spec['think']) * spec['out']) / 1e6
        return round(cost('ideas', IDEA_MODEL) + cost('notes', NOTES_MODEL), 4)


def tokens(value):
    return math.ceil(len(value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)) / 4)


class CountingPool:
    """The notes pool, with its calls counted."""
    def __init__(self, pool, meter): self.pool, self.meter = pool, meter
    def __getattr__(self, name): return getattr(self.pool, name)
    def generate(self, parts, **kwargs):
        reply = self.pool.generate(parts, **kwargs)
        self.meter.calls['notes'] += 1
        self.meter.tokens['notes'][0] += tokens(parts) + tokens(kwargs.get('system') or '')
        self.meter.tokens['notes'][1] += tokens(reply[0])
        return reply


def brief(case):
    return {'destination': case['destination'], 'planning_strategy': 'personal_places', 'travelers': {'count': case['travelers']},
            'date_range': {'arrival': case['days'][0], 'departure': case['days'][1]}, 'interests': case['interests'],
            'preference_tags': case['tags'], 'custom_instructions': case['text']}


def judge(case, result):
    """Automatic checks only. Whether the plan is one you'd enjoy still needs a person to read it."""
    places = {p['id']: p for p in result['places']}
    days = result['itinerary']['days']
    stops = [(d, s, places[s['place_id']]) for d in days for s in d['stops']]
    import unicodedata
    plain = lambda text: unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode().casefold()
    names = ' | '.join(plain(p['name']) for _, _, p in stops)
    wanted = set(categories(normalized_brief(brief(case))))
    used = {p['category'] for _, _, p in stops}
    meals = [sum(p['category'] == 'food' for dd, _, p in stops if dd is d) for d in days]
    # Between stops only: the first leg of a day is the ride from the stay to that day's part of town.
    legs = [s.get('travel_time_minutes') or 0 for _, s, _ in stops if s.get('travel_from') != 'base']
    reasons = sum(bool((p.get('reason') or p.get('why_recommended') or '').strip()) for _, _, p in stops)
    ids = [s['place_id'] for _, s, _ in stops]
    community = sum(any(n.startswith('community:') for n in p.get('library_node_ids', []) or []) for _, _, p in stops)
    return {
        'days': len(days), 'stops': len(stops), 'stops_per_day': round(len(stops) / max(1, len(days)), 1),
        'every_day_has_stops': all(d['stops'] for d in days),
        'two_meals_a_day': all(m >= 2 for m in meals), 'meals_per_day': meals,
        'categories_missing': sorted(wanted - used - {'event'}),
        'must_sees_missing': [m for m in case['must'] if not any(option in names for option in m.split('|'))],
        'max_leg_minutes': max(legs or [0]), 'legs_ok': max(legs or [0]) <= MAX_LEG_MINUTES,
        'no_repeats': len(ids) == len(set(ids)),
        'stops_with_a_reason': f'{reasons}/{len(stops)}',
        'from_community_videos': community,
        'status': result['delivery_status'],
    }


def passed(q):
    return (q['every_day_has_stops'] and q['two_meals_a_day'] and not q['categories_missing'] and not q['must_sees_missing']
            and q['legs_ok'] and q['no_repeats'])


def run_case(case, generate, cache, notes, meter, osm):
    out = {}
    nodes = []
    if case.get('videos'):
        normal = normalized_brief(brief(case))
        nodes = plan_nodes(normal, videos=community_videos().all(), takes=place_takes(), plan_categories=categories(normal))
    for label in ('cold', 'again'):
        before, start = meter.snapshot(), time.time()
        provider = GeminiBlendProvider(cached_generate(generate, cache, IDEA_MODEL), [cached_resolver(osm, cache)])
        with tempfile.TemporaryDirectory() as directory:
            result = run(brief(case), directory=directory, root=ROOT, place_provider=provider, fallback_provider=FallbackChain(ROOT),
                         community_nodes=nodes, notes_pool=notes)
        calls = {k: meter.calls[k] - before['calls'][k] for k in meter.calls}
        out[label] = {'seconds': round(time.time() - start, 1), 'calls': calls, 'paid_tier_usd': meter.usd(before),
                      'ideas': len(provider.report), 'ideas_kept': sum(r['kept'] for r in provider.report),
                      'dropped': sorted({r['reason'] for r in provider.report if r['reason']}),
                      'quality': judge(case, result), 'community_nodes': len(nodes)}
        out[label]['pass'] = passed(out[label]['quality'])
        out[label]['plan'] = [[f"{s['time']} {next(p for p in result['places'] if p['id'] == s['place_id'])['category'][:6]:6} "
                               f"{next(p for p in result['places'] if p['id'] == s['place_id'])['name']}" for s in d['stops']]
                              for d in result['itinerary']['days']]
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--only'); parser.add_argument('--json'); parser.add_argument('--no-notes', action='store_true')
    parser.add_argument('--keep-cache', action='store_true', help='reuse the cache from an earlier run (shows a warm city)')
    args = parser.parse_args()
    key = read_environment(ROOT / '.env').get('GEMINI_API_KEY', '').strip()
    if not key: sys.exit('GEMINI_API_KEY is needed for the live path')
    meter = Meter()
    ideas = GeminiPool(key, [IDEA_MODEL, 'gemini-3.5-flash-lite', 'gemini-3.1-flash-lite'], timeout=150)

    def generate(prompt, system, schema):
        reply = ideas.generate([{'text': prompt}], system=system, schema=schema, temperature=0.4)[0]
        meter.calls['ideas'] += 1
        meter.tokens['ideas'][0] += tokens(prompt) + tokens(system); meter.tokens['ideas'][1] += tokens(reply)
        return reply
    raw = osm_resolver()

    def osm(query, destination, near, kinds=None):
        meter.calls['osm'] += 1
        return raw(query, destination, near, kinds)
    osm.label = 'openstreetmap'; osm.takes_kinds = True
    path = ROOT / '.local/tmp/cost-quality-cache.sqlite'
    if not args.keep_cache:
        for extra in ('', '-wal', '-shm'):
            Path(str(path) + extra).unlink(missing_ok=True)
    cache = PlaceCache(path)
    notes = None if args.no_notes else CountingPool(GeminiPool(key, None), meter)
    report = {}
    for case in CASES:
        if args.only and args.only != case['id']: continue
        print(f"\n=== {case['id']}: {case['destination']}, {case['days'][0]} to {case['days'][1]}", flush=True)
        try:
            report[case['id']] = run_case(case, generate, cache, notes, meter, osm)
        except Exception as error:  # noqa: BLE001 - one city failing must not hide the others
            report[case['id']] = {'error': f'{type(error).__name__}: {error}'[:300]}
            print('  FAILED', report[case['id']]['error'], flush=True); continue
        for label, r in report[case['id']].items():
            q = r['quality']
            print(f"  {label:5} {'PASS' if r['pass'] else 'CHECK'}  {r['seconds']:>6}s  ideas {r['calls']['ideas']}  osm {r['calls']['osm']}  notes {r['calls']['notes']}"
                  f"  ≈${r['paid_tier_usd']}  kept {r['ideas_kept']}/{r['ideas']}  stops/day {q['stops_per_day']}  meals {q['meals_per_day']}"
                  f"  missing {q['categories_missing'] + q['must_sees_missing']}  max leg {q['max_leg_minutes']}m  reasons {q['stops_with_a_reason']}"
                  f"  videos {q['from_community_videos']}", flush=True)
        for index, day in enumerate(report[case['id']]['cold']['plan']):
            print(f'    day {index + 1}: ' + '; '.join(day), flush=True)
    if args.json: Path(args.json).write_text(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()
