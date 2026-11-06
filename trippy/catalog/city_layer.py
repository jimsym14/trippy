"""Free, generic city knowledge layer from Wikidata, Wikipedia and Wikivoyage.

For any city in the catalog this collects, without paid APIs or models:

* **Notable places** – Wikipedia pages geotagged inside the city extent, joined
  to Wikidata for fame (number of language editions, "sitelinks"), type, labels,
  short description, coordinates (P625), website (P856) and image (P18).
  Licence: Wikidata CC0; Wikipedia only used for discovery.
* **Curated listings** – Wikivoyage See/Do/Eat/Drink/Buy listings from the city
  article and its district sub-pages: name, coordinates, Wikidata link, short
  description. Licence: CC BY-SA 4.0 – excerpts must keep attribution.

    .venv/bin/python -m trippy.catalog.city_layer --city Barcelona   # or --all

Output: ``.local/city_layer/<city>/{wikidata,wikivoyage,manifest}.json``.
Every HTTP response is cached under ``.local/city_layer/http-cache`` so an
interrupted run resumes without re-requesting. Requests are spaced out and back
off on HTTP 429/503 as Wikimedia's API etiquette asks.
"""
from datetime import datetime, timezone
from hashlib import sha256
import json
import math
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

from .boundaries import city_extent, city_slug, catalog_cities

ALLOWED_HOSTS = {'en.wikipedia.org', 'www.wikidata.org', 'en.wikivoyage.org'}
USER_AGENT = 'TrippyCityLayer/0.2 (open-data travel research; bounded, cached)'
MIN_SITELINKS = 5            # below this, an item is rarely a visitor destination
GEO_RADIUS_M = 2500          # Wikipedia geosearch radius per grid point
GEO_SPACING_KM = 3.0
MAX_GRID_POINTS = 400
LISTING_TYPES = ('see', 'do', 'eat', 'drink', 'buy')
MAX_CONTENT_CHARS = 400


class Fetcher:
    def __init__(self, cache_dir, min_interval=2.0, max_attempts=8, log=print):
        self.cache = Path(cache_dir); self.cache.mkdir(parents=True, exist_ok=True)
        self.min_interval, self.max_attempts, self.log = min_interval, max_attempts, log
        self._last = 0.0
        self.requests = self.cache_hits = 0

    def get(self, host, **params):
        if host not in ALLOWED_HOSTS:
            raise ValueError('Untrusted host ' + host)
        query = urlencode(sorted({**params, 'format': 'json', 'formatversion': 2, 'maxlag': 5}.items()))
        url = f'https://{host}/w/api.php?{query}'
        path = self.cache / (sha256(url.encode()).hexdigest() + '.json')
        if path.is_file():
            self.cache_hits += 1
            return json.loads(path.read_text())
        delay = 5
        for attempt in range(self.max_attempts):
            wait = self.min_interval - (time.monotonic() - self._last)
            if wait > 0: time.sleep(wait)
            self._last = time.monotonic()
            try:
                with urlopen(Request(url, headers={'User-Agent': USER_AGENT, 'Accept': 'application/json'}),
                             timeout=60) as response:
                    if urlparse(response.url).hostname not in ALLOWED_HOSTS:
                        raise ValueError('Unexpected redirect')
                    data = json.loads(response.read(20_000_001))
            except HTTPError as exc:
                if exc.code not in (429, 500, 502, 503, 504):
                    raise
                retry = exc.headers.get('Retry-After')
                pause = min(int(retry) if retry and retry.isdigit() else delay, 300)
                self.log(json.dumps({'phase': 'backoff', 'host': host, 'status': exc.code, 'seconds': pause}))
                time.sleep(pause); delay = min(delay * 2, 300); continue
            except URLError:
                time.sleep(delay); delay = min(delay * 2, 300); continue
            if isinstance(data, dict) and data.get('error', {}).get('code') == 'maxlag':
                time.sleep(delay); continue
            self.requests += 1
            path.write_text(json.dumps(data, ensure_ascii=False))
            return data
        raise RuntimeError(f'Giving up on {host} after {self.max_attempts} attempts')


def grid(bbox, spacing_km=GEO_SPACING_KM):
    xmin, ymin, xmax, ymax = bbox
    lat_step = spacing_km / 111.0
    lon_step = spacing_km / (111.0 * math.cos(math.radians((ymin + ymax) / 2)))
    points, lat = [], ymin + lat_step / 2
    while lat < ymax:
        lon = xmin + lon_step / 2
        while lon < xmax:
            points.append((round(lat, 5), round(lon, 5))); lon += lon_step
        lat += lat_step
    if len(points) > MAX_GRID_POINTS:
        raise ValueError('City extent too large for one bounded run')
    return points or [((ymin + ymax) / 2, (xmin + xmax) / 2)]


def _claim_ids(entity, prop):
    return [c['mainsnak'].get('datavalue', {}).get('value', {}).get('id')
            for c in entity.get('claims', {}).get(prop, []) if c.get('mainsnak', {}).get('datavalue')]


def _claim_value(entity, prop):
    for c in entity.get('claims', {}).get(prop, []):
        value = c.get('mainsnak', {}).get('datavalue', {}).get('value')
        if value is not None:
            return value
    return None


def collect_wikidata(fetcher, bbox, languages=('en', 'es', 'ca', 'fr', 'de', 'it', 'el')):
    qids = {}
    for lat, lon in grid(bbox):
        data = fetcher.get('en.wikipedia.org', action='query', generator='geosearch', ggscoord=f'{lat}|{lon}',
                           ggsradius=GEO_RADIUS_M, ggslimit=500, prop='pageprops', ppprop='wikibase_item')
        for page in data.get('query', {}).get('pages', []):
            q = page.get('pageprops', {}).get('wikibase_item')
            if q: qids[q] = page['title']
    entities = {}
    ids = sorted(qids)
    for i in range(0, len(ids), 50):
        data = fetcher.get('www.wikidata.org', action='wbgetentities', ids='|'.join(ids[i:i + 50]),
                           props='sitelinks|claims|labels|descriptions|aliases', languages='|'.join(languages))
        entities.update(data.get('entities', {}))
    items = []
    for qid, entity in entities.items():
        coord = _claim_value(entity, 'P625')
        sitelinks = len(entity.get('sitelinks', {}))
        if not isinstance(coord, dict) or sitelinks < MIN_SITELINKS:
            continue
        lat, lon = coord.get('latitude'), coord.get('longitude')
        if lat is None or not (bbox[1] <= lat <= bbox[3] and bbox[0] <= lon <= bbox[2]):
            continue
        image = _claim_value(entity, 'P18')
        items.append({
            'qid': qid, 'sitelinks': sitelinks, 'latitude': lat, 'longitude': lon,
            'labels': {k: v['value'] for k, v in entity.get('labels', {}).items()},
            'aliases': sorted({a['value'] for v in entity.get('aliases', {}).values() for a in v})[:20],
            'description': (entity.get('descriptions', {}).get('en') or {}).get('value'),
            'classes': [c for c in _claim_ids(entity, 'P31') if c],
            'website': _claim_value(entity, 'P856') if isinstance(_claim_value(entity, 'P856'), str) else None,
            'image': image if isinstance(image, str) else None,
            'enwiki': qids.get(qid)})
    # Class labels let the planner classify items by name ("basilica", "park")
    # without hard-coding Wikidata IDs.
    classes = sorted({c for item in items for c in item['classes']})
    class_labels = {}
    for i in range(0, len(classes), 50):
        data = fetcher.get('www.wikidata.org', action='wbgetentities', ids='|'.join(classes[i:i + 50]),
                           props='labels', languages='en')
        for cid, entity in data.get('entities', {}).items():
            class_labels[cid] = (entity.get('labels', {}).get('en') or {}).get('value')
    return {'items': sorted(items, key=lambda x: (-x['sitelinks'], x['qid'])), 'class_labels': class_labels}


_LISTING = re.compile(r'\{\{\s*(see|do|eat|drink|buy|listing)\s*\|', re.I)


def _templates(text):
    for match in _LISTING.finditer(text):
        depth, i = 0, match.start()
        while i < len(text):
            if text.startswith('{{', i): depth += 1; i += 2
            elif text.startswith('}}', i):
                depth -= 1; i += 2
                if depth == 0: break
            else: i += 1
        yield match.group(1).lower(), text[match.start() + 2:i - 2]


def _clean(value):
    value = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]*)\]\]', r'\1', value)       # [[link|label]]
    value = re.sub(r'\[https?://\S+\s([^\]]*)\]', r'\1', value)           # [url label]
    value = re.sub(r"'{2,}", '', value)
    value = re.sub(r'\{\{[^{}]*\}\}', '', value)
    value = re.sub(r'<[^>]+>', '', value)
    return re.sub(r'\s+', ' ', value).strip()


def parse_listing(kind, body):
    fields, depth, current = {}, 0, ''
    parts = []
    for ch in body:
        if ch in '{[': depth += 1
        elif ch in '}]': depth -= 1
        if ch == '|' and depth == 0:
            parts.append(current); current = ''
        else:
            current += ch
    parts.append(current)
    for part in parts[1:]:
        if '=' in part:
            k, v = part.split('=', 1)
            fields[k.strip().lower()] = v.strip()
    if kind == 'listing':
        kind = fields.get('type', '').lower()
    if kind not in LISTING_TYPES or not fields.get('name'):
        return None
    def number(key):
        try: return float(fields.get(key, '').strip())
        except ValueError: return None
    wikidata = fields.get('wikidata', '').strip()
    return {'type': kind, 'name': _clean(fields['name']), 'alt': _clean(fields.get('alt', '')) or None,
            'latitude': number('lat'), 'longitude': number('long'),
            'wikidata': wikidata if re.fullmatch(r'Q\d+', wikidata) else None,
            'address': _clean(fields.get('address', '')) or None,
            'url': fields.get('url', '').strip() if fields.get('url', '').strip().startswith('https://') else None,
            'content': _clean(fields.get('content', '') or fields.get('description', ''))[:MAX_CONTENT_CHARS] or None}


def collect_wikivoyage(fetcher, city, max_pages=40):
    titles, seen, pages = [city], set(), []
    while titles and len(pages) < max_pages:
        title = titles.pop(0)
        if title in seen: continue
        seen.add(title)
        data = fetcher.get('en.wikivoyage.org', action='parse', page=title, prop='wikitext', redirects=1)
        if 'parse' not in data:
            continue
        text = data['parse']['wikitext']
        real = data['parse']['title']
        listings = [l for l in (parse_listing(k, b) for k, b in _templates(text)) if l]
        for listing in listings:
            listing['page'] = real
        pages.append({'title': real, 'url': 'https://en.wikivoyage.org/wiki/' + real.replace(' ', '_'),
                      'revid': data['parse'].get('revid'), 'listings': listings})
        # District articles are sub-pages ("Barcelona/Ciutat Vella").
        titles += sorted({m for m in re.findall(r'\[\[(' + re.escape(real) + r'/[^\]|#]+)', text)} - seen)
    return {'pages': pages, 'licence': 'CC BY-SA 4.0 (Wikivoyage); keep attribution to page URL'}


def fetch_city(root, city, *, log=print):
    root = Path(root)
    bbox, country = city_extent(root, city)
    out = root / '.local/city_layer' / city_slug(city)
    out.mkdir(parents=True, exist_ok=True)
    fetcher = Fetcher(root / '.local/city_layer/http-cache', log=log)
    wikivoyage = collect_wikivoyage(fetcher, city)
    (out / 'wikivoyage.json').write_text(json.dumps(wikivoyage, ensure_ascii=False, indent=1))
    log(json.dumps({'phase': 'wikivoyage', 'pages': len(wikivoyage['pages']),
                    'listings': sum(len(p['listings']) for p in wikivoyage['pages'])}))
    wikidata = collect_wikidata(fetcher, bbox)
    (out / 'wikidata.json').write_text(json.dumps(wikidata, ensure_ascii=False, indent=1))
    log(json.dumps({'phase': 'wikidata', 'items': len(wikidata['items'])}))
    manifest = {'city': city, 'country': country, 'bbox': list(bbox),
                'retrieved_at': datetime.now(timezone.utc).isoformat(),
                'wikidata_items': len(wikidata['items']), 'wikivoyage_pages': len(wikivoyage['pages']),
                'wikivoyage_listings': sum(len(p['listings']) for p in wikivoyage['pages']),
                'http_requests': fetcher.requests, 'cache_hits': fetcher.cache_hits,
                'licences': {'wikidata': 'CC0', 'wikivoyage': 'CC BY-SA 4.0'}}
    (out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    return manifest


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Collect the free Wikidata/Wikivoyage city layer')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--city'); group.add_argument('--all', action='store_true')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    for name in (catalog_cities(args.root) if args.all else [args.city]):
        print(json.dumps(fetch_city(args.root, name), ensure_ascii=False), flush=True)
