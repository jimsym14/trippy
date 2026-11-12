"""Write ready-made line files for busy cities (data/transit/lines/<city>.json).

The server answers /api/transit from its month cache, then from these files, then from Overpass. Overpass is
slow for big networks (Barcelona ~35 s) and often busy for shared cloud servers, so the cities people plan most
are shipped ready. Re-run every few months: `python3 scripts/transit_seed_lines.py [city ...]`.
"""
import json
import sys
import time
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from trippy import transit  # noqa: E402
from trippy.planner.osm_places import overpass  # noqa: E402

CITIES = {
    'athens': (37.9795, 23.7280), 'rome': (41.8960, 12.4823), 'barcelona': (41.3874, 2.1686), 'lisbon': (38.7223, -9.1393),
    'paris': (48.8566, 2.3522), 'madrid': (40.4168, -3.7038), 'milan': (45.4642, 9.1900), 'berlin': (52.5200, 13.4050),
    'amsterdam': (52.3676, 4.9041), 'vienna': (48.2082, 16.3738), 'prague': (50.0755, 14.4378), 'london': (51.5072, -0.1276),
}

def main(names):
    out_dir = Path(__file__).resolve().parents[1] / 'data/transit/lines'
    out_dir.mkdir(parents=True, exist_ok=True)
    for name in names or CITIES:
        lat, lon = CITIES[name]
        started = time.time()
        try:
            found = transit.lines_from(overpass(transit.query(lat, lon)))
        except Exception as error:  # noqa: BLE001
            print(name, 'failed', type(error).__name__, error); continue
        if not found:
            print(name, 'no lines (Overpass busy?), kept the old file'); continue
        (out_dir / f'{name}.json').write_text(json.dumps({'city': name, 'latitude': lat, 'longitude': lon, 'fetched': date.today().isoformat(),
                                                          'attribution': '© OpenStreetMap contributors', 'lines': found}, separators=(',', ':')))
        print(name, len(found), 'lines', round(time.time() - started), 's')
        time.sleep(5)   # be kind to the free service

if __name__ == '__main__':
    main(sys.argv[1:])
