"""Offline use of the free city layer (trippy.catalog.city_layer) for ranking.

Gives every city a generic "what is worth seeing / eating here" signal:

* Wikidata fame: number of Wikipedia language editions (sitelinks), scaled
  ``log2(sitelinks / 4)`` and capped at 4 (8 → 1, 16 → 2, 32 → 3, 64+ → 4).
* Wikivoyage listing: a curated See/Do/Eat/Drink/Buy entry adds a fixed bonus.

Entries are linked to catalog rows when a name matches and the two points are
within ``LINK_RADIUS_M``. Notable entries without a catalog row become their
own candidates, located by the entry's own cited coordinates (Wikidata P625 or
the Wikivoyage listing), never by a model. Classification uses the English
labels of Wikidata classes, so no class IDs are hard-coded.
"""
from collections import defaultdict
from hashlib import sha256
import json
import math
from pathlib import Path
import statistics

from .candidate_quality import distance_km
from .endorsements import name_key
from .search_intent import themes_in

VERSION = 'city-evidence-v1'
LINK_RADIUS_M = 150
FAME_CAP = 4.0
LISTING_BONUS = {'see': 1.5, 'do': 1.0, 'eat': 2.0, 'drink': 2.0, 'buy': 1.0}
STANDALONE_MIN_SITELINKS = 8
# (keyword in class label, planner family, pseudo source category)
CLASS_RULES = [
    ('art museum', 'sights', 'art_museum'), ('museum', 'sights', 'museum'), ('gallery', 'sights', 'art_gallery'),
    ('basilica', 'sights', 'landmark'), ('cathedral', 'sights', 'landmark'), ('church', 'sights', 'landmark'),
    ('chapel', 'sights', 'landmark'), ('monastery', 'sights', 'landmark'), ('temple', 'sights', 'landmark'),
    ('mosque', 'sights', 'landmark'), ('synagogue', 'sights', 'landmark'), ('palace', 'sights', 'palace'),
    ('castle', 'sights', 'castle'), ('fortress', 'sights', 'castle'), ('tower', 'sights', 'landmark'),
    ('monument', 'sights', 'landmark'), ('memorial', 'sights', 'landmark'), ('fountain', 'sights', 'landmark'),
    ('architectural', 'sights', 'landmark'), ('archaeological', 'sights', 'landmark'), ('ruins', 'sights', 'landmark'),
    ('amphitheatre', 'sights', 'landmark'), ('aqueduct', 'sights', 'landmark'), ('town square', 'sights', 'landmark'),
    ('plaza', 'sights', 'landmark'), ('tourist attraction', 'sights', 'landmark'), ('viewpoint', 'sights', 'landmark'),
    ('observation', 'sights', 'landmark'), ('stadium', 'sights', 'landmark'), ('opera house', 'sights', 'landmark'),
    ('concert hall', 'sights', 'landmark'), ('theatre', 'sights', 'landmark'), ('market', 'sights', 'landmark'),
    ('football venue', 'sights', 'landmark'), ('square', 'sights', 'landmark'),
    ('zoo', 'sights', 'zoo'), ('aquarium', 'sights', 'aquarium'), ('botanical garden', 'outdoors', 'botanical_garden'),
    ('garden', 'outdoors', 'park'), ('park', 'outdoors', 'park'), ('beach', 'outdoors', 'beach'),
    ('mountain', 'outdoors', 'park'), ('hill', 'outdoors', 'park'), ('nature reserve', 'outdoors', 'park'),
]
# Famous buildings are often typed only as "building"/"house"; accept them
# when fame is high enough to make them a destination.
# (Casa Milà and Casa Batlló are typed "residential building").
GENERIC_RULES = [('house', 25), ('building', 25), ('residential', 25), ('mansion', 15), ('villa', 15),
                 ('structure', 30), ('skyscraper', 35)]
# Never visitor stops, however famous: places that are areas, people, events or services.
EXCLUDE = ('human', 'station', 'metro', 'railway', 'street', 'avenue', 'road', 'district', 'neighbourhood',
           'neighborhood', 'quarter', 'hotel', 'company', 'business', 'organization', 'school', 'university',
           'college', 'embassy', 'consulate', 'club', 'team', 'event', 'festival', 'court', 'prison', 'police',
           'airport', 'cemetery', 'municipality', 'city', 'province', 'comarca', 'parish', 'electoral',
           'shopping centre', 'shopping mall', 'country', 'principality')
LISTING_FAMILY = {'see': ('sights', 'landmark'), 'do': ('sights', 'activity'), 'eat': ('food', 'restaurant'),
                  'drink': ('nightlife', 'bar'), 'buy': ('shopping', 'shopping')}


def fame(sitelinks):
    return max(0.0, min(FAME_CAP, math.log2(max(sitelinks, 1) / 4)))


def classify(item, class_labels):
    labels = [(class_labels.get(c) or '').casefold() for c in item['classes']]
    if any(any(word in label for word in EXCLUDE) for label in labels):
        return None
    for keyword, family, category in CLASS_RULES:
        if any(keyword in label for label in labels):
            return family, category
    for keyword, needed in GENERIC_RULES:
        if any(keyword in label for label in labels) and item['sitelinks'] >= needed:
            return 'sights', 'landmark'
    return None


def _keys(names):
    return {k for k in (name_key(n) for n in names if n) if len(k) >= 3}


# A catalog row may carry the evidence only if it is the same kind of place:
# "Souvenirs Sagrada Família" must never inherit the basilica's fame.
COMPATIBLE_FAMILIES = {'sights': {'sights', 'outdoors'}, 'outdoors': {'outdoors', 'sights'},
                       'food': {'food', 'nightlife', 'coffee'}, 'nightlife': {'nightlife', 'food'},
                       'shopping': {'shopping'}}


def _match_strength(a, b):
    """2 = identical normalized name, 1 = one name's words contain the other's, 0 = no match."""
    best = 0
    for x in a:
        for y in b:
            if x == y:
                return 2
            tx, ty = set(x.split()), set(y.split())
            small, large = sorted((tx, ty), key=len)
            # Containment must cover most of the longer name: "Santa Maria" is
            # not "Galería de Santa Maria Novella".
            if len(small) >= 2 and small <= large and len(small) / len(large) >= 0.6:
                best = 1
    return best


def _read(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def layer_dir(root, city):
    from trippy.catalog.boundaries import city_slug
    return Path(root) / '.local/city_layer' / city_slug(city)


def build(root, city, catalog_rows):
    """catalog_rows: iterable of dicts with entity_id, name, family, latitude, longitude."""
    directory = layer_dir(root, city)
    wikidata = _read(directory / 'wikidata.json') or {'items': [], 'class_labels': {}}
    wikivoyage = _read(directory / 'wikivoyage.json') or {'pages': []}
    cells = defaultdict(list)
    for row in catalog_rows:
        cells[(round(row['latitude'] / 0.002), round(row['longitude'] / 0.002))].append(row)

    def nearby(lat, lon):
        ci, cj = round(lat / 0.002), round(lon / 0.002)
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                for row in cells.get((ci + di, cj + dj), ()):
                    if distance_km(lat, lon, row['latitude'], row['longitude']) * 1000 <= LINK_RADIUS_M:
                        yield row

    entries = {}

    def entry(key, **base):
        return entries.setdefault(key, {'score': 0.0, 'sources': [], 'themes': set(), 'wikivoyage': [], **base})

    class_labels = wikidata.get('class_labels', {})
    for item in wikidata.get('items', []):
        kind = classify(item, class_labels)
        if not kind:
            continue
        names = [*item['labels'].values(), *item.get('aliases', [])]
        e = entry('wd:' + item['qid'], qid=item['qid'], name=item['labels'].get('en') or next(iter(item['labels'].values()), item['qid']),
                  names=names, latitude=item['latitude'], longitude=item['longitude'], family=kind[0],
                  source_category=kind[1], website=item.get('website'), sitelinks=item['sitelinks'],
                  description=item.get('description'))
        e['score'] += fame(item['sitelinks'])
        e['sources'].append({'id': 'wikidata-' + item['qid'], 'url': f"https://www.wikidata.org/wiki/{item['qid']}",
                             'publisher': 'Wikidata', 'type': 'reference', 'checked_at': None})
        evidence = ' '.join([*names, item.get('description') or '', *(class_labels.get(c) or '' for c in item['classes'])])
        e['themes'] |= set(themes_in(evidence))
    by_qid = {e['qid']: k for k, e in entries.items() if e.get('qid')}
    for page in wikivoyage.get('pages', []):
        for listing in page['listings']:
            family, category = LISTING_FAMILY[listing['type']]
            key = by_qid.get(listing.get('wikidata')) or 'wv:' + sha256(
                f"{listing['name']}|{listing.get('latitude')}|{listing.get('longitude')}".encode()).hexdigest()[:16]
            e = entry(key, name=listing['name'], names=[listing['name'], listing.get('alt')],
                      latitude=listing.get('latitude'), longitude=listing.get('longitude'),
                      family=family, source_category=category, website=listing.get('url'),
                      address=listing.get('address'), sitelinks=0, description=None)
            if e.get('latitude') is None and listing.get('latitude') is not None:
                e['latitude'], e['longitude'] = listing['latitude'], listing['longitude']
            e['address'] = e.get('address') or listing.get('address')
            if not e['wikivoyage']:
                e['score'] += LISTING_BONUS[listing['type']]
            e['wikivoyage'].append({'type': listing['type'], 'page': page['title'], 'url': page['url'],
                                    'content': listing.get('content')})
            if not any(s['url'] == page['url'] for s in e['sources']):
                e['sources'].append({'id': 'wikivoyage-' + sha256(page['url'].encode()).hexdigest()[:12],
                                     'url': page['url'], 'publisher': 'Wikivoyage (CC BY-SA 4.0)',
                                     'type': 'guide', 'checked_at': None})
            e['themes'] |= set(themes_in(' '.join(filter(None, [listing['name'], listing.get('content')]))))
    linked, standalone = {}, []
    for key, e in entries.items():
        e['themes'] = sorted(e['themes'])
        e['score'] = round(min(e['score'], 5.0), 2)
        if e.get('latitude') is None:
            continue                    # never placed on a map without cited coordinates
        keys = _keys(e['names'])
        allowed = COMPATIBLE_FAMILIES.get(e['family'], {e['family']})
        candidates = [(strength, r) for r in nearby(e['latitude'], e['longitude']) if r['family'] in allowed
                      for strength in [_match_strength(keys, _keys([r['name']]))] if strength]
        match = min(candidates, key=lambda c: (-c[0], distance_km(e['latitude'], e['longitude'],
                                                                   c[1]['latitude'], c[1]['longitude'])),
                    default=(0, None))[1]
        if match is not None:
            current = linked.get(match['entity_id'])
            if current is None or e['score'] > current['score']:
                linked[match['entity_id']] = {**e, 'match_basis': 'name_and_distance'}
        elif e['sitelinks'] >= STANDALONE_MIN_SITELINKS or e['wikivoyage']:
            standalone.append({**e, 'entity_id': key.replace(':', '-')})
    top = sorted((e for e in entries.values() if e.get('latitude') is not None and e['sitelinks']),
                 key=lambda e: -e['sitelinks'])[:40]
    core = [statistics.median(e['latitude'] for e in top), statistics.median(e['longitude'] for e in top)] if len(top) >= 5 else None
    return {'version': VERSION, 'city': city, 'entities': linked, 'standalone': standalone, 'core': core,
            'counts': {'wikidata_classified': sum(1 for e in entries.values() if e.get('qid')),
                       'wikivoyage_listings': sum(len(p['listings']) for p in wikivoyage.get('pages', [])),
                       'linked': len(linked), 'standalone': len(standalone)}}


_memory = {}


def load(root, city, catalog_rows_fn):
    """Cached evidence; rebuilt when the layer files or the catalog change."""
    directory = layer_dir(root, city)
    if not (directory / 'wikidata.json').is_file() and not (directory / 'wikivoyage.json').is_file():
        return None
    parts = [VERSION] + [str((directory / f).stat().st_mtime_ns) if (directory / f).exists() else '-'
                         for f in ('wikidata.json', 'wikivoyage.json')]
    catalog = Path(root) / '.local/catalog.sqlite'
    parts.append(str(catalog.stat().st_mtime_ns) if catalog.exists() else '-')
    fp = sha256('|'.join(parts).encode()).hexdigest()
    if (str(root), city, fp) not in _memory:
        _memory[(str(root), city, fp)] = build(root, city, catalog_rows_fn())
    return _memory[(str(root), city, fp)]
