"""Build a "where to stay" density grid for one city from OpenStreetMap (Overpass).

The iOS app builds the same grid live; this script makes a bundled copy so a
city opens instantly. Usage:
    python scripts/stay_grid.py Barcelona 41.3874 2.1686 out.json [--from raw.json]
"""
import json
import math
import sys
import urllib.parse
import urllib.request

ROWS = COLS = 28
HALF_LAT = 0.055
MIRRORS = ['https://overpass-api.de/api/interpreter', 'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
           'https://overpass.kumi.systems/api/interpreter']
LAYERS = [
    ('sights', 'nwr["tourism"~"^(attraction|museum|gallery|viewpoint)$"]', 'center'),
    ('food', 'node["amenity"~"^(restaurant|cafe)$"]', 'skel'),
    ('night', 'node["amenity"~"^(bar|pub|nightclub)$"]', 'skel'),
    ('green', 'way["leisure"="park"]', 'center'),
    ('transit', 'node["railway"~"^(station|subway_entrance|tram_stop)$"]', 'skel'),
    ('budget', 'nwr["tourism"~"^(hostel|guest_house)$"]', 'center'),
    ('hotel', 'nwr["tourism"="hotel"]', 'center'),
]


def bbox(lat, lon):
    half_lon = HALF_LAT / math.cos(math.radians(lat))
    return lat - HALF_LAT, lon - half_lon, lat + HALF_LAT, lon + half_lon


def query(box):
    b = ','.join(f'{v:.5f}' for v in box)
    parts = ['[out:json][timeout:40];']
    for name, selector, mode in LAYERS:
        parts.append(f'make m name="{name}";out;{selector}({b});out {mode} qt;')
    parts.append(f'make m name="places";out;node["place"~"^(suburb|neighbourhood|quarter)$"]({b});out qt;')
    return ''.join(parts)


def fetch(box):
    data = urllib.parse.urlencode({'data': query(box)}).encode()
    for url in MIRRORS:
        try:
            req = urllib.request.Request(url, data=data, headers={'User-Agent': 'Trippy/0.1 (trip planner prototype)'})
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as exc:  # try the next mirror
            print('mirror failed', url, exc, file=sys.stderr)
    raise SystemExit('all Overpass mirrors failed')


def grid(city, raw, box):
    south, west, north, east = box
    layers = {name: [0] * (ROWS * COLS) for name, *_ in LAYERS}
    places, current = [], None
    for e in raw['elements']:
        if e['type'] == 'm':
            current = e['tags']['name']; continue
        lat = e.get('lat', (e.get('center') or {}).get('lat'))
        lon = e.get('lon', (e.get('center') or {}).get('lon'))
        if lat is None or lon is None: continue
        if current == 'places':
            name = (e.get('tags') or {}).get('name')
            if name: places.append({'name': name, 'lat': round(lat, 5), 'lon': round(lon, 5)})
            continue
        r = int((north - lat) / (north - south) * ROWS); c = int((lon - west) / (east - west) * COLS)
        if 0 <= r < ROWS and 0 <= c < COLS: layers[current][r * COLS + c] += 1
    return {'city': city, 'south': south, 'west': west, 'north': north, 'east': east,
            'rows': ROWS, 'cols': COLS, 'layers': layers, 'places': places, 'source': 'OpenStreetMap contributors (ODbL)'}


if __name__ == '__main__':
    city, lat, lon, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
    box = bbox(lat, lon)
    raw = json.load(open(sys.argv[6])) if '--from' in sys.argv else fetch(box)
    json.dump(grid(city, raw, box), open(out, 'w'), separators=(',', ':'), ensure_ascii=False)
    print('wrote', out)
