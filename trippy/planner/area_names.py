"""Names for planned areas ("Trastevere", "Monti"), free from OpenStreetMap.

One Nominatim reverse lookup per area centre at neighbourhood zoom, at most one
request a second as its usage policy asks, cached on disk. Without a network the
area is named after its best-known place ("around Pantheon").
"""
from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

FIELDS = ('neighbourhood', 'quarter', 'suburb', 'city_district', 'borough', 'village', 'town')


def reverse(latitude, longitude, language='en'):
    query = urllib.parse.urlencode({'lat': f'{latitude:.5f}', 'lon': f'{longitude:.5f}', 'format': 'jsonv2', 'zoom': 16,
                                    'accept-language': language})
    from trippy import usage
    usage.hit('free:nominatim')
    request = urllib.request.Request('https://nominatim.openstreetmap.org/reverse?' + query,
                                     headers={'User-Agent': 'Trippy/1.0 (travel planner)'})
    with urllib.request.urlopen(request, timeout=10) as response:
        address = json.load(response).get('address') or {}
    # The historic quarter is the name people use (Trastevere, Monti, Gràcia); an
    # administrative district ("Municipio Roma I", "District 3") is not.
    for field in ('quarter', 'neighbourhood', 'suburb', 'city_district', 'borough', 'village', 'town'):
        value = address.get(field)
        if value and not any(value.startswith(w) for w in ('Municipio', 'District', 'Arrondissement', 'Bezirk', 'Distrito')):
            return value
    return None


def name_areas(root, areas, *, lookup=reverse, log=lambda *a: None, pause=1.1):
    cache_file = Path(root) / '.local/area-names.json'
    try: cache = json.loads(cache_file.read_text())
    except (OSError, ValueError): cache = {}
    asked = False
    for area in areas:
        key = f"{area['latitude']:.3f},{area['longitude']:.3f}"
        if key not in cache:
            if asked: time.sleep(pause)
            try: cache[key] = lookup(area['latitude'], area['longitude'])
            except Exception as error:  # noqa: BLE001 - names are optional
                log('area_name_failed', {'error': type(error).__name__}); cache[key] = None
            asked = True
        area['name'] = cache[key] or f"around {area['anchor_name']}"
        area['name_source'] = 'openstreetmap' if cache[key] else 'anchor_place'
    # Two areas with one name read as one place: keep the name on the stronger one.
    seen = {}
    for area in sorted(areas, key=lambda a: -a['importance']):
        if area['name'] in seen: area['name'] = f"{area['name']} · {area['anchor_name']}"
        seen[area['name']] = True
    try:
        cache_file.parent.mkdir(parents=True, exist_ok=True); cache_file.write_text(json.dumps(cache, ensure_ascii=False))
    except OSError:
        pass
