"""City neighbourhood boundaries from Overture Divisions, for any catalog city.

Fetch (explicit network operation, public non-requester-pays assets only):

    .venv/bin/python -m trippy.catalog.boundaries --city Barcelona
    .venv/bin/python -m trippy.catalog.boundaries --all

The extent of each city is the bounding box of its own published catalog rows,
so no per-city configuration is needed. Areas (Overture subtypes locality,
macrohood, neighborhood, microhood) are written to
``.local/boundaries/<city>/areas.geojsonl`` with a manifest recording release,
source assets, licences and checksum. Lookups are offline:

    index = AreaIndex.load(root, 'Barcelona')
    index.resolve('Gràcia')          -> matching areas (names in any language)
    index.contains(areas, lat, lon)  -> point-in-polygon

A city without a boundary file simply returns ``None`` from ``AreaIndex.load``;
callers must then label any text-based area matching as such.
"""
from datetime import datetime, timezone
from hashlib import sha256
import json
import os
from pathlib import Path
import re
import sqlite3
import struct
from urllib.parse import urlparse

from .acquire import STAC, get_json, overlaps

SUBTYPES = ('locality', 'macrohood', 'neighborhood', 'microhood')
MAX_AREAS = 20000
MAX_BYTES = 96_000_000
# Catalog extents are padded so edge neighbourhoods are fully included.
PAD_DEGREES = 0.01
GENERIC_TOKENS = {'the', 'de', 'la', 'el', 'del', 'les', 'els', 'l', 'd', 'of', 'barri', 'quarter',
                  'district', 'districte', 'distrito', 'neighbourhood', 'neighborhood'}


def city_slug(city):
    return re.sub(r'[^a-z0-9]+', '-', area_key(city, keep_generic=True)).strip('-') or 'city'


def area_key(value, keep_generic=False):
    import unicodedata
    text = ''.join(c for c in unicodedata.normalize('NFD', str(value).casefold()) if not unicodedata.combining(c))
    tokens = re.sub(r'[^a-z0-9]+', ' ', text).split()
    if not keep_generic:
        tokens = [t for t in tokens if t not in GENERIC_TOKENS]
    return ' '.join(tokens)


def city_extent(root, city):
    """Bounding box (xmin, ymin, xmax, ymax) and country of a city's catalog rows."""
    path = Path(root) / '.local/catalog.sqlite'
    with sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True) as db:
        row = db.execute('''SELECT min(cs.longitude), min(cs.latitude), max(cs.longitude), max(cs.latitude),
                max(g.country_code) FROM catalog_snapshots cs
            JOIN catalog_versions cv ON cv.id=cs.catalog_version_id
            JOIN geographies g ON g.id=cv.geography_id
            WHERE lower(g.name)=lower(?) AND cv.status='published' ''', (city,)).fetchone()
    if row is None or row[0] is None:
        raise ValueError(f'No published catalog rows for {city}')
    bbox = (float(row[0]) - PAD_DEGREES, float(row[1]) - PAD_DEGREES,
            float(row[2]) + PAD_DEGREES, float(row[3]) + PAD_DEGREES)
    return bbox, row[4]


def catalog_cities(root):
    path = Path(root) / '.local/catalog.sqlite'
    with sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True) as db:
        return [r[0] for r in db.execute('''SELECT DISTINCT g.name FROM geographies g
            JOIN catalog_versions cv ON cv.geography_id=g.id WHERE cv.status='published' ORDER BY 1''')]


def discover(release=None, bbox=None):
    root = get_json(STAC + '/catalog.json')
    release = release or root['latest']
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}\.\d+', release):
        raise ValueError('Invalid pinned Overture release')
    collection_url = f'{STAC}/{release}/divisions/division_area/collection.json'
    collection = get_json(collection_url)
    links = [v['href'] for v in collection['links'] if v['rel'] == 'item']
    if not links or len(links) > 100:
        raise ValueError('Unsupported STAC collection size')
    selected = []
    for item in map(get_json, links):
        if not overlaps(item['bbox'], bbox):
            continue
        asset = item['assets']['aws']
        parsed = urlparse(asset['href'])
        if (parsed.scheme != 'https' or parsed.hostname != 'overturemaps-us-west-2.s3.us-west-2.amazonaws.com'
                or '/theme=divisions/type=division_area/' not in parsed.path):
            raise ValueError('Unexpected division area asset')
        if item['properties'].get('storage:schemes', {}).get('aws', {}).get('requester_pays') is not False:
            raise ValueError('Only public, non-requester-pays source assets are allowed')
        selected.append({'url': asset['href'], 'item_id': item['id'], 'bbox': item['bbox'],
                         'remote_file_bytes': asset.get('file:size')})
    if not selected or len(selected) > 8:
        raise ValueError('City extent must intersect between one and eight source assets')
    return {'provider': 'overture', 'theme': 'divisions/division_area', 'release': release,
            'collection_url': collection_url, 'bbox': list(bbox), 'assets': selected,
            'retrieved_at': datetime.now(timezone.utc).isoformat()}


# --- WKB polygons -------------------------------------------------------------

def parse_wkb(value):
    """Decode 2D WKB Polygon/MultiPolygon to a list of polygons (lists of rings)."""
    data = bytes(value)
    def read(offset):
        endian = '<' if data[offset] == 1 else '>'
        kind = struct.unpack_from(endian + 'I', data, offset + 1)[0]
        offset += 5
        if kind == 3:
            rings, offset = polygon(endian, offset)
            return [rings], offset
        if kind == 6:
            count = struct.unpack_from(endian + 'I', data, offset)[0]; offset += 4
            polygons = []
            for _ in range(count):
                parts, offset = read(offset)
                polygons.extend(parts)
            return polygons, offset
        raise ValueError(f'Unsupported area geometry type {kind}')
    def polygon(endian, offset):
        count = struct.unpack_from(endian + 'I', data, offset)[0]; offset += 4
        rings = []
        for _ in range(count):
            points = struct.unpack_from(endian + 'I', data, offset)[0]; offset += 4
            coords = struct.unpack_from(endian + 'd' * (2 * points), data, offset); offset += 16 * points
            rings.append([[round(coords[i], 7), round(coords[i + 1], 7)] for i in range(0, len(coords), 2)])
        return rings, offset
    polygons, _ = read(0)
    return polygons


def fetch_city(root, city, *, release=None, workspace=None, force=False):
    """Explicit network operation: download one city's areas. Never overwrites unless forced."""
    import duckdb
    root = Path(root)
    out_dir = root / '.local/boundaries' / city_slug(city)
    output, manifest_path = out_dir / 'areas.geojsonl', out_dir / 'manifest.json'
    if output.exists() and not force:
        raise FileExistsError(f'{output} exists; pass --force to refresh')
    bbox, country = city_extent(root, city)
    manifest = discover(release, bbox)
    workspace = Path(workspace or root / '.local/stage3/duckdb').resolve()
    connection = duckdb.connect(config={'memory_limit': '512MB', 'threads': 2,
        'extension_directory': str(workspace / 'extensions'), 'temp_directory': str(workspace / 'temp')})
    try:
        try:
            connection.execute('LOAD httpfs')
        except duckdb.Error:
            connection.execute("INSTALL httpfs FROM 'https://extensions.duckdb.org'"); connection.execute('LOAD httpfs')
        connection.execute('SET http_timeout=60'); connection.execute('SET http_retries=2')
        paths = [a['url'] for a in manifest['assets']]
        columns = {v[0] for v in connection.execute('DESCRIBE SELECT * FROM read_parquet(?)', [paths]).fetchall()}
        if not {'id', 'geometry', 'subtype', 'names', 'bbox', 'country'} <= columns:
            raise ValueError('Unsupported division_area schema; do not silently reinterpret columns')
        where = ('bbox.xmin<=? AND bbox.xmax>=? AND bbox.ymin<=? AND bbox.ymax>=? AND subtype IN (%s)'
                 % ','.join('?' * len(SUBTYPES)))
        params = [paths, bbox[2], bbox[0], bbox[3], bbox[1], *SUBTYPES]
        if country:
            where += ' AND country=?'; params.append(country)
        rows = connection.execute(
            'SELECT id, division_id, subtype, class, names.primary, map_values(names.common), country, '
            'admin_level, geometry::BLOB, bbox, sources FROM read_parquet(?) WHERE ' + where + ' LIMIT ?',
            [*params, MAX_AREAS + 1]).fetchall()
        if len(rows) > MAX_AREAS:
            raise ValueError('Too many areas for one city extent')
        out_dir.mkdir(parents=True, exist_ok=True)
        tmp = output.with_suffix('.partial')
        written = 0
        with tmp.open('w', encoding='utf-8') as stream:
            for (aid, division_id, subtype, klass, primary, common, ctry, level, wkb, box, sources) in rows:
                try:
                    polygons = parse_wkb(wkb)
                except (ValueError, struct.error):
                    continue
                names = sorted({n for n in [primary, *(common or [])] if n})
                line = json.dumps({'id': aid, 'division_id': division_id, 'subtype': subtype, 'class': klass,
                    'name': primary, 'names': names, 'country': ctry, 'admin_level': level,
                    'bbox': [box['xmin'], box['ymin'], box['xmax'], box['ymax']], 'polygons': polygons,
                    'sources': [{k: s.get(k) for k in ('dataset', 'license', 'record_id')} for s in sources or []]},
                    ensure_ascii=False) + '\n'
                written += len(line.encode())
                if written > MAX_BYTES:
                    raise ValueError('Area extract exceeds the byte ceiling')
                stream.write(line)
        os.replace(tmp, output)
        manifest.update({'city': city, 'country': country, 'areas': len(rows), 'artifact_bytes': written,
                         'sha256': sha256(output.read_bytes()).hexdigest(), 'subtypes': list(SUBTYPES),
                         'duckdb_version': duckdb.__version__,
                         'licence_note': 'Overture Maps divisions; per-row source licences retained'})
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
        return manifest
    finally:
        connection.close()


# --- offline lookup -----------------------------------------------------------

def _in_ring(lon, lat, ring):
    inside = False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]; xj, yj = ring[j]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / ((yj - yi) or 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def area_contains(area, lat, lon):
    box = area['bbox']
    if not (box[0] <= lon <= box[2] and box[1] <= lat <= box[3]):
        return False
    return any(_in_ring(lon, lat, rings[0]) and not any(_in_ring(lon, lat, h) for h in rings[1:])
               for rings in area['polygons'] if rings)


class AreaIndex:
    def __init__(self, city, areas, manifest=None):
        self.city, self.areas, self.manifest = city, areas, manifest or {}
        locality_key = area_key(city)
        # The city's own locality polygon, when present, scopes ambiguous names
        # ("Centre" exists in many neighbouring towns).
        self.locality = [a for a in areas if a['subtype'] == 'locality'
                         and any(area_key(n) == locality_key for n in a['names'])]
        self._cache = {}

    @classmethod
    def load(cls, root, city):
        directory = Path(root) / '.local/boundaries' / city_slug(city)
        path = directory / 'areas.geojsonl'
        if not path.is_file():
            return None
        areas = [json.loads(line) for line in path.read_text(encoding='utf-8').splitlines() if line.strip()]
        manifest = json.loads((directory / 'manifest.json').read_text()) if (directory / 'manifest.json').is_file() else {}
        return cls(city, areas, manifest)

    def _in_city(self, area):
        if not self.locality or area['subtype'] == 'locality':
            return True
        lon = (area['bbox'][0] + area['bbox'][2]) / 2; lat = (area['bbox'][1] + area['bbox'][3]) / 2
        return any(area_contains(l, lat, lon) for l in self.locality)

    def resolve(self, hint):
        """Areas whose name (any language) equals the hint, ignoring accents and articles."""
        k = area_key(hint)
        if not k:
            return []
        if k not in self._cache:
            matches = [a for a in self.areas if a['subtype'] != 'locality'
                       and any(area_key(n) == k for n in a['names'])]
            # With a known city polygon, names elsewhere (a neighbouring town's
            # "Centre") never count; without one, all matches are returned.
            self._cache[k] = [a for a in matches if self._in_city(a)] if self.locality else matches
        return self._cache[k]

    def mentioned_in(self, text):
        """Name of the most specific-looking area named in free text, or None.

        Whole-word match on folded names of this city's areas; the longest name
        wins so "Vila de Gràcia" beats "Gràcia". Short names (< 5 letters) are
        ignored to avoid accidental hits.
        """
        folded = ' ' + area_key(text) + ' '
        hits = {}
        for a in self.areas:
            if a['subtype'] == 'locality' or (self.locality and not self._in_city(a)):
                continue
            for n in a['names']:
                k = area_key(n)
                if len(k) >= 5 and f' {k} ' in folded and len(k) > len(hits.get(a['name'], '')):
                    hits[a['name']] = k
        # A shorter name inside a longer matched one is the same mention.
        keys = set(hits.values())
        distinct = {name: k for name, k in hits.items()
                    if not any(k != other and f' {k} ' in f' {other} ' for other in keys)}
        # Several areas named ("we stay in Sant Antoni, want Sagrada Família and
        # Montjuïc") describe a city-wide trip, not a focus on one of them.
        if len({k for k in distinct.values()}) != 1:
            return None
        return max(hits.items(), key=lambda kv: len(kv[1]))[0]

    @staticmethod
    def contains(areas, lat, lon):
        return any(area_contains(a, lat, lon) for a in areas)

    def names_at(self, lat, lon):
        return sorted({a['name'] for a in self.areas if a['subtype'] != 'locality' and area_contains(a, lat, lon)})


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Download Overture neighbourhood areas for catalog cities')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--city'); group.add_argument('--all', action='store_true')
    parser.add_argument('--release'); parser.add_argument('--force', action='store_true')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    for name in (catalog_cities(args.root) if args.all else [args.city]):
        result = fetch_city(args.root, name, release=args.release, force=args.force)
        print(json.dumps({'city': name, 'areas': result['areas'], 'bytes': result['artifact_bytes'],
                          'release': result['release']}, ensure_ascii=False))
