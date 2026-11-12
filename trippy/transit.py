"""A city's public transport on demand: its lines to draw on the map, and which ticket is worth buying.

Lines come from OpenStreetMap route relations (metro, tram, light rail, funicular) through Overpass: free, and
kept for a month in the planner cache, so a city is fetched once for everybody. Ticket prices cannot come from
an open database (none exists), so they are a small hand-kept table (data/transit/tickets.json), each city with
the operator's page and the day it was read. `advise` does the arithmetic the traveller would otherwise do at
the machine: singles, bundles and passes for their days and rides, cheapest first.
"""
import json
import math
import time
import unicodedata
from datetime import date
from pathlib import Path

MODES = {'subway': 'Metro', 'light_rail': 'Light rail', 'tram': 'Tram', 'monorail': 'Monorail', 'funicular': 'Funicular'}
ORDER = list(MODES)
RADIUS = 14000
LINES_DAYS = 30
STALE_DAYS = 183


def city_key(name):
    text = unicodedata.normalize('NFKD', (name or '').split(',')[0]).encode('ascii', 'ignore').decode().casefold()
    return ' '.join(text.split())


def _metres(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    return math.hypot((a[0] - b[0]) * 111320, (a[1] - b[1]) * 111320 * math.cos(lat))


def _thin(points, step=35):
    """Drop points closer than `step` metres to the last one kept: the line looks the same and weighs a fifth."""
    if len(points) < 3: return points
    out = [points[0]]
    for point in points[1:-1]:
        if _metres(out[-1], point) >= step: out.append(point)
    out.append(points[-1])
    return out


def _stitch(segments):
    """Member ways arrive unordered; join the ones that share an end into as few paths as possible."""
    paths = [list(s) for s in segments if len(s) >= 2]
    merged = True
    while merged:
        merged = False
        for i in range(len(paths)):
            for j in range(i + 1, len(paths)):
                a, b = paths[i], paths[j]
                if _metres(a[-1], b[0]) < 12: paths[i] = a + b[1:]
                elif _metres(a[-1], b[-1]) < 12: paths[i] = a + b[-2::-1]
                elif _metres(a[0], b[-1]) < 12: paths[i] = b + a[1:]
                elif _metres(a[0], b[0]) < 12: paths[i] = b[::-1] + a[1:]
                else: continue
                del paths[j]; merged = True; break
            if merged: break
    return paths


def lines_from(elements):
    """Overpass route relations (out geom) → one drawable line per mode and line number, both directions merged."""
    lines = {}
    for element in elements:
        tags = element.get('tags') or {}
        mode = tags.get('route')
        if element.get('type') != 'relation' or mode not in MODES: continue
        ref = (tags.get('ref') or tags.get('name') or '').strip()[:24]
        if not ref: continue
        segments, stops = [], []
        for member in element.get('members') or []:
            if member.get('type') == 'way' and member.get('geometry') and not (member.get('role') or '').startswith('platform'):
                segments.append([(round(p['lat'], 5), round(p['lon'], 5)) for p in member['geometry']])
            elif member.get('type') == 'node' and (member.get('role') or '').startswith('stop') and member.get('lat') is not None:
                stops.append((round(member['lat'], 5), round(member['lon'], 5)))
        length = sum(_metres(a, b) for s in segments for a, b in zip(s, s[1:]))
        if length < 400: continue
        colour = (tags.get('colour') or tags.get('color') or '').strip().lstrip('#')
        line = {'id': f'{mode}:{ref}', 'mode': mode, 'mode_title': MODES[mode], 'ref': ref,
                'name': (tags.get('name:en') or tags.get('name') or ref)[:120],
                'color': colour.upper() if len(colour) == 6 and all(c in '0123456789abcdefABCDEF' for c in colour) else None,
                'operator': (tags.get('operator') or tags.get('network') or '')[:80] or None,
                'metres': round(length), 'segments': segments, 'stops': stops}
        # Each direction is its own relation; the longer one is the whole line.
        if line['id'] not in lines or length > lines[line['id']]['metres']:
            line['stops'] = stops or lines.get(line['id'], {}).get('stops', [])
            lines[line['id']] = line
    out = []
    for line in lines.values():
        paths = [_thin(path) for path in _stitch(line.pop('segments'))]
        seen, stops = set(), []
        for stop in line['stops']:
            spot = (round(stop[0], 4), round(stop[1], 4))
            if spot not in seen: seen.add(spot); stops.append(list(stop))
        out.append({**line, 'paths': [[list(p) for p in path] for path in paths], 'stops': stops, 'km': round(line['metres'] / 1000, 1)})
    def order(line):
        digits = ''.join(c for c in line['ref'] if c.isdigit())
        return (ORDER.index(line['mode']), int(digits) if digits else 999, line['ref'])
    return sorted(out, key=order)


def query(latitude, longitude, radius=RADIUS):
    kinds = '|'.join(MODES)
    return f'[out:json][timeout:90];relation["type"="route"]["route"~"^({kinds})$"](around:{radius},{latitude},{longitude});out geom;'


SEEDS = Path(__file__).resolve().parents[1] / 'data/transit/lines'
SEED_METRES = 15000


def seed(latitude, longitude, root=SEEDS):
    """A ready-made line file for a city within 15 km (scripts/transit_seed_lines.py), or None."""
    best = None
    for path in sorted(Path(root).glob('*.json')) if Path(root).is_dir() else []:
        try: value = json.loads(path.read_text())
        except (OSError, ValueError): continue
        metres = _metres((latitude, longitude), (value.get('latitude', 0), value.get('longitude', 0)))
        if metres <= SEED_METRES and value.get('lines') and (best is None or metres < best[0]): best = (metres, value)
    if best is None: return None
    value = best[1]
    return {'lines': value['lines'], 'attribution': value.get('attribution') or '© OpenStreetMap contributors', 'fetched': value.get('fetched')}


def lines(latitude, longitude, *, fetch, cache=None, seeds=SEEDS):
    """The lines around a point: the month cache, else a ready-made file for the big cities, else Overpass.
    `fetch(query)` returns Overpass elements; when it fails, an older ready-made file is still better than nothing,
    and with none the error goes up so the app can say "try again" instead of "this city has no metro"."""
    key = cache.key(round(latitude, 1), round(longitude, 1)) if cache else None
    if cache:
        found, value = cache.get('transit', key, LINES_DAYS)
        if found: return value
    ready = seed(latitude, longitude, seeds)
    if ready and ready.get('fetched') and (date.today() - date.fromisoformat(ready['fetched'])).days <= STALE_DAYS:
        return ready
    try:
        value = {'lines': lines_from(fetch(query(latitude, longitude))), 'attribution': '© OpenStreetMap contributors',
                 'fetched': date.today().isoformat()}
    except Exception:
        if ready: return ready
        raise
    if not value['lines'] and ready: return ready
    if cache and value['lines']: cache.put('transit', key, value)
    return value


# Every scheduled service a traveller can board, for "which line goes there": buses and coaches included.
BOARDABLE = {'subway': 'Metro', 'light_rail': 'Light rail', 'tram': 'Tram', 'monorail': 'Monorail', 'funicular': 'Funicular',
             'train': 'Train', 'bus': 'Bus', 'trolleybus': 'Trolleybus', 'coach': 'Coach', 'ferry': 'Ferry'}
BOARD_ORDER = list(BOARDABLE)
NEAR_METRES = 450


def near_query(latitude, longitude, radius=NEAR_METRES):
    kinds = '|'.join(BOARDABLE)
    return (f'[out:json][timeout:40];(node(around:{radius},{latitude},{longitude})["public_transport"~"^(stop_position|platform|station)$"];'
            f'node(around:{radius},{latitude},{longitude})["highway"="bus_stop"];node(around:{radius},{latitude},{longitude})["railway"~"^(station|halt|tram_stop)$"];'
            f'way(around:{radius},{latitude},{longitude})["public_transport"="platform"];)->.stops;'
            f'relation(bn.stops)["type"="route"]["route"~"^({kinds})$"]->.a;relation(bw.stops)["type"="route"]["route"~"^({kinds})$"]->.b;(.a;.b;);out tags;')


def lines_near(latitude, longitude, *, fetch, cache=None):
    """The lines that stop within a short walk of a point: metro, tram, train, bus, coach and ferry. Names and
    numbers only (no shapes), so the answer is small. Kept a month per ~100 m square."""
    key = cache.key('near', round(latitude, 3), round(longitude, 3)) if cache else None
    if cache:
        found, value = cache.get('transit', key, LINES_DAYS)
        if found: return value
    seen = {}
    for element in fetch(near_query(latitude, longitude)):
        tags = element.get('tags') or {}
        mode, ref = tags.get('route'), (tags.get('ref') or '').strip()[:16]
        if element.get('type') != 'relation' or mode not in BOARDABLE or not ref: continue
        network = (tags.get('network') or tags.get('operator') or '')[:60]
        colour = (tags.get('colour') or '').strip().lstrip('#')
        # Both directions of a line are one line; where it runs between is kept from the first seen.
        seen.setdefault((mode, ref, network), {
            'id': f'{mode}:{ref}:{network}', 'mode': mode, 'mode_title': BOARDABLE[mode], 'ref': ref, 'network': network or None,
            'color': colour.upper() if len(colour) == 6 and all(c in '0123456789abcdefABCDEF' for c in colour) else None,
            'from': (tags.get('from') or '')[:60] or None, 'to': (tags.get('to') or '')[:60] or None,
            'international': bool(tags.get('service') in {'international', 'long_distance', 'high_speed'} or mode == 'coach')})
    def order(line):
        digits = ''.join(c for c in line['ref'] if c.isdigit())
        return (BOARD_ORDER.index(line['mode']), int(digits) if digits else 9999, line['ref'])
    value = sorted(seen.values(), key=order)
    if cache: cache.put('transit', key, value)
    return value


def between(start, end, *, fetch, cache=None):
    """Which lines connect two points without a change: the ones that stop near both. This is not a route
    planner (no timetable, no changes); it answers "is there a direct line, and which one" for free."""
    try: a = lines_near(*start, fetch=fetch, cache=cache)
    except Exception: a = None  # noqa: BLE001
    try: b = lines_near(*end, fetch=fetch, cache=cache)
    except Exception: b = None  # noqa: BLE001
    there = {line['id'] for line in b or []}
    direct = [line for line in a or [] if line['id'] in there]
    return {'direct': direct, 'from': a or [], 'to': b or [], 'known': a is not None and b is not None,
            'attribution': '© OpenStreetMap contributors'}


def tickets(root, city):
    """The hand-kept ticket table for a city, or None when we have not checked that city yet."""
    table = json.loads((Path(root) / 'data/transit/tickets.json').read_text(encoding='utf-8'))['cities']
    found = table.get(city_key(city))
    if not found: return None
    age = (date.today() - date.fromisoformat(found['checked'])).days
    return {**found, 'stale': age > STALE_DAYS}


def advise(table, *, days, rides_per_day, travelers=1, airport=False, fare='full'):
    """Ways to pay for `days` in the city at `rides_per_day`, cheapest first, as totals per person.

    Each option is one simple thing to buy (singles, a bundle topped up with singles, or passes), never a puzzle.
    With `airport`, the two airport trips are added to whatever does not already include them."""
    days, rides = max(1, int(days)), max(0, int(round(days * rides_per_day)))
    # The reduced fare (students, seniors, children: whoever the operator says) replaces the price where one exists.
    # Tickets with no reduced price stay at full fare, so the comparison is still honest.
    items = [{**t, 'price': t['reduced']} if fare == 'reduced' and t.get('reduced') else t for t in table['tickets']]
    single = min((t for t in items if t['kind'] == 'single'), key=lambda t: t['price'], default=None)
    airport_one = min((t for t in items if t['kind'] == 'airport'), key=lambda t: t['price'], default=None)
    airport_return = next((t for t in items if t['kind'] == 'airport_return'), None)
    airport_cost = 0.0
    if airport and airport_one:
        airport_cost = min(2 * airport_one['price'], airport_return['price'] if airport_return else 9e9)

    def option(label, total, buy, includes_airport, note=None):
        extra = 0.0 if includes_airport or not airport else airport_cost
        return {'label': label, 'buy': buy, 'per_person': round(total + extra, 2), 'total': round((total + extra) * max(1, travelers), 2),
                'airport_extra': round(extra, 2), 'note': note}
    options = []
    if single and rides:
        options.append(option(f"{rides} × {single['name']}", rides * single['price'], [{'id': single['id'], 'count': rides}],
                              bool(single.get('airport')) and airport_one is None, single.get('note')))
    for bundle in (t for t in items if t['kind'] == 'bundle'):
        if not rides: continue
        shared = bundle.get('shared') and travelers > 1
        need = rides * travelers if shared else rides
        packs = max(1, need // bundle['rides'])
        left = max(0, need - packs * bundle['rides'])
        # A second pack only when the leftover singles would cost more than it.
        if single and left * single['price'] > bundle['price']: packs += 1; left = 0
        total = packs * bundle['price'] + left * (single['price'] if single else 0)
        if shared: total /= travelers
        buy = [{'id': bundle['id'], 'count': packs}] + ([{'id': single['id'], 'count': left}] if left and single else [])
        label = f"{packs} × {bundle['name']}" + (f" + {left} single{'s' if left != 1 else ''}" if left else '') + (' for everyone' if shared else '')
        options.append(option(label, total, buy, False, bundle.get('note')))
    for ticket in (t for t in items if t['kind'] == 'pass'):
        span = ticket['hours'] / 24
        count = math.ceil(days / span)
        # A pass much longer than the stay is listed only when one of it covers everything.
        if count > 1 and span > 1 and count * span > days + 1: continue
        if count * span > days * 3 and count == 1 and span > 3: continue
        label = ticket['name'] if count == 1 else f"{count} × {ticket['name']}"
        options.append(option(label, count * ticket['price'], [{'id': ticket['id'], 'count': count}], bool(ticket.get('airport')), ticket.get('note')))
    options.sort(key=lambda o: (o['per_person'], len(o['buy'])))
    if options:
        options[0]['best'] = True
        if len(options) > 1: options[0]['saves'] = round(options[-1]['per_person'] - options[0]['per_person'], 2)
    return {'days': days, 'rides': rides, 'travelers': travelers, 'airport': bool(airport and airport_cost), 'options': options[:5],
            'fare': fare if fare == 'reduced' and any(t.get('reduced') for t in table['tickets']) else 'full'}


def answer(root, city, latitude, longitude, *, fetch, cache=None, days=3, rides_per_day=4, travelers=1, airport=False, fare='full', clock=time.time):
    """Everything the app's transit sheet shows for one city."""
    started = clock()
    try: network = lines(latitude, longitude, fetch=fetch, cache=cache)
    except Exception as error:  # noqa: BLE001 - tickets are still worth showing when the map source is down
        # "unavailable", not an empty network: the app offers to try again rather than saying the city has no metro.
        network = {'lines': [], 'attribution': '', 'error': type(error).__name__, 'status': 'unavailable'}
    table = tickets(root, city)
    by_mode = {}
    for line in network['lines']: by_mode.setdefault(line['mode_title'], []).append(line['ref'])
    return {'city': city, **network, 'modes': [{'title': t, 'lines': refs} for t, refs in by_mode.items()],
            'tickets': table, 'advice': advise(table, days=days, rides_per_day=rides_per_day, travelers=travelers, airport=airport, fare=fare) if table else None,
            'seconds': round(clock() - started, 2)}
