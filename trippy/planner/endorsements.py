"""Link creator-recommended source venues to broad-inventory catalog identities.

The video source pack knows *which* places are worth visiting but has no
canonical identity or coordinates; the Overture catalog has identities and
coordinates but no notion of quality.  This module joins them conservatively:

* exact normalized-name equality only (diacritics, case, punctuation and a
  few generic tokens such as "Barcelona" are ignored), no fuzzy matching;
* the catalog family must be compatible with the source venue's categories;
* several compatible rows are accepted only when they are near-duplicates of
  one place (all within ``DUPLICATE_RADIUS_KM``); otherwise the venue stays
  unresolved and is reported as ambiguous;
* negative creator stances never add an endorsement.

Every link is ``review_status: unreviewed`` and is used only as a ranking
signal for a row that already has its own catalog identity and coordinates.
It never creates a place, a pin, a coordinate or a factual claim.  Reviewers
can reject or force links through ``.local/stage3/endorsement-overrides.json``:

    {"reject_entity_ids": ["<entity>"], "links": {"<source record id>": "<entity>"}}
"""
from collections import defaultdict
from hashlib import sha256
import json
from pathlib import Path
import re
import sqlite3
import statistics
import unicodedata

from .candidate_quality import distance_km
from .search_intent import themes_in

VERSION = 'endorsements-v2'
CACHE = '.local/stage3/endorsements-v1.json'
OVERRIDES = '.local/stage3/endorsement-overrides.json'
ACTIVE_DATASET = '.local/stage3/planner-release-v1/active-dataset.json'
DUPLICATE_RADIUS_KM = 0.4
DOMINANT_CONFIDENCE = 0.95
DOMINANT_MARGIN = 0.15
# Automatic links need a confident, addressed catalog row; weaker rows are
# frequently mislocated crowd-sourced pages and go to human review instead.
AUTO_LINK_MIN_CONFIDENCE = 0.8
GENERIC_TOKENS = {'barcelona', 'bcn', 'the', 'de', 'la', 'el', 'del', 'les', 'els', 'l', 'd', 'of'}
STANCE_POINTS = {'recommended': 3.0, 'passing': 1.5, 'mixed': 0.5}
SOURCE_FAMILIES = {
    'sights': {'sights', 'outdoors'}, 'museums': {'sights'}, 'outdoors': {'outdoors', 'sights'},
    'day_trips': {'outdoors', 'sights'}, 'events': {'sights', 'nightlife'},
    'food': {'food', 'nightlife', 'coffee'}, 'bars': {'nightlife', 'food'},
    'coffee': {'coffee', 'food'}, 'shopping': {'shopping', 'food'},
    'family_accessibility': {'sights', 'outdoors'},
}


def name_key(value):
    text = ''.join(c for c in unicodedata.normalize('NFD', str(value).casefold())
                   if not unicodedata.combining(c))
    tokens = [t for t in re.sub(r'[^a-z0-9]+', ' ', text).split() if t not in GENERIC_TOKENS]
    return ' '.join(tokens)


def _opinion(record):
    for claim in record.get('claims', []):
        if claim.get('basis') == 'creator_opinion' and claim.get('value'):
            return claim['value'][:400]
    return None


def _read_json(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return None


def source_venues(root):
    """Return (bundle_id, venue drafts) from the active private source dataset, if any."""
    active = _read_json(Path(root) / ACTIVE_DATASET)
    if not active or not active.get('normalized'):
        return None, []
    normalized = _read_json(Path(root) / active['normalized'])
    if not normalized:
        return None, []
    venues = [r for r in normalized.get('drafts', []) if r.get('kind') == 'venue']
    return active.get('bundle_sha256') or active.get('edition_id'), venues


def build(root, city='Barcelona'):
    root = Path(root)
    bundle, venues = source_venues(root)
    catalog = root / '.local/catalog.sqlite'
    empty = {'version': VERSION, 'city': city, 'bundle': bundle, 'entities': {}, 'ambiguous': [],
             'unmatched': [], 'needs_review': [], 'core': None}
    if not venues or not catalog.is_file():
        return empty
    overrides = _read_json(root / OVERRIDES) or {}
    rejected = set(overrides.get('reject_entity_ids', []))
    forced = overrides.get('links', {})
    by_key = defaultdict(list); by_id = {}
    with sqlite3.connect(catalog.resolve().as_uri() + '?mode=ro', uri=True) as db:
        db.row_factory = sqlite3.Row
        rows = db.execute('''SELECT cs.entity_id, cs.name, cs.family, cs.source_category, cs.confidence,
                cs.latitude, cs.longitude, cs.address FROM catalog_snapshots cs
            JOIN catalog_versions cv ON cv.id=cs.catalog_version_id
            JOIN geographies g ON g.id=cv.geography_id
            WHERE lower(g.name)=lower(?) AND cv.status='published'
            AND (cs.operating_status IS NULL OR cs.operating_status!='permanently_closed')''', (city,))
        for row in rows:
            row = dict(row); by_id[row['entity_id']] = row
            k = name_key(row['name'])
            if k: by_key[k].append(row)
    entities, ambiguous, unmatched, needs_review = {}, [], [], []
    for venue in venues:
        stance = venue.get('stance')
        if stance not in STANCE_POINTS:
            continue
        families = set().union(*(SOURCE_FAMILIES.get(c, set()) for c in venue.get('categories', [])))
        if venue['id'] in forced and forced[venue['id']] in by_id:
            chosen, basis = by_id[forced[venue['id']]], 'reviewer_link'
        else:
            keys = {name_key(n) for n in [venue['name'], *venue.get('aliases', [])]}
            keys = {k for k in keys if len(k) >= 4}
            hits = {r['entity_id']: r for k in keys for r in by_key.get(k, []) if r['family'] in families}
            hits = {i: r for i, r in hits.items() if i not in rejected}
            if not hits:
                unmatched.append({'record_id': venue['id'], 'name': venue['name']}); continue
            ranked = sorted(hits.values(), key=lambda r: (-float(r['confidence'] or 0), r['entity_id']))
            best = ranked[0]
            spread = max(distance_km(float(best['latitude']), float(best['longitude']),
                                     float(r['latitude']), float(r['longitude'])) for r in ranked)
            basis = 'exact_normalized_name_compatible_family'
            if spread > DUPLICATE_RADIUS_KM:
                # Crowd-sourced duplicates are often mislocated low-confidence
                # copies of a landmark. Accept only a clearly dominant row.
                runner_up = float(ranked[1]['confidence'] or 0)
                if float(best['confidence'] or 0) >= DOMINANT_CONFIDENCE and float(best['confidence']) - runner_up >= DOMINANT_MARGIN:
                    basis = 'exact_normalized_name_dominant_confidence'
                else:
                    ambiguous.append({'record_id': venue['id'], 'name': venue['name'],
                                      'candidate_entity_ids': sorted(hits)}); continue
            if float(best['confidence'] or 0) < AUTO_LINK_MIN_CONFIDENCE or not best.get('address'):
                needs_review.append({'record_id': venue['id'], 'name': venue['name'],
                                     'proposed_entity_id': best['entity_id'], 'catalog_name': best['name'],
                                     'reason': 'low_confidence_or_missing_address'}); continue
            chosen = best
        entry = entities.setdefault(chosen['entity_id'], {
            'entity_id': chosen['entity_id'], 'catalog_name': chosen['name'], 'family': chosen['family'],
            'latitude': float(chosen['latitude']), 'longitude': float(chosen['longitude']),
            'match_basis': basis, 'review_status': 'reviewer_linked' if basis == 'reviewer_link' else 'unreviewed',
            'occurrences': []})
        source = venue.get('source') or {}
        evidence = ' '.join([venue['name'], *(c.get('value') or '' for c in venue.get('claims', []))])
        entry['themes'] = sorted(set(entry.get('themes', [])) | set(themes_in(evidence)))
        entry['occurrences'].append({
            'record_id': venue['id'], 'name': venue['name'], 'stance': stance,
            'publisher_group': venue.get('publisher_group'), 'url': source.get('url'),
            'published_at': venue.get('published_at'), 'opinion': _opinion(venue)})
    for entry in entities.values():
        # One creator channel counts once per stance, however many videos it made.
        best_by_group = {}
        for occ in entry['occurrences']:
            group = occ['publisher_group'] or occ['url']
            best_by_group[group] = max(best_by_group.get(group, 0), STANCE_POINTS[occ['stance']])
        entry['publisher_groups'] = len(best_by_group)
        entry['score'] = sum(best_by_group.values())
    core = None
    if len(entities) >= 5:
        core = [statistics.median(e['latitude'] for e in entities.values()),
                statistics.median(e['longitude'] for e in entities.values())]
    return {**empty, 'entities': entities, 'ambiguous': ambiguous, 'unmatched': unmatched,
            'needs_review': needs_review, 'core': core}


def _fingerprint(root):
    root = Path(root)
    parts = [VERSION]
    for rel in (ACTIVE_DATASET, OVERRIDES, '.local/catalog.sqlite'):
        path = root / rel
        parts.append(f'{rel}:{path.stat().st_mtime_ns if path.exists() else None}')
    return sha256('|'.join(parts).encode()).hexdigest()


_memory = {}


def load(root, city='Barcelona'):
    """Return cached endorsements, rebuilding when any input changed."""
    root = Path(root)
    if not (root / ACTIVE_DATASET).is_file():
        return {'version': VERSION, 'entities': {}, 'core': None, 'ambiguous': [], 'unmatched': []}
    fp = _fingerprint(root)
    if (root, city, fp) in _memory:
        return _memory[(root, city, fp)]
    cached = _read_json(root / CACHE)
    if not (cached and cached.get('fingerprint') == fp and cached.get('city') == city):
        cached = {**build(root, city), 'fingerprint': fp}
        try:
            (root / CACHE).write_text(json.dumps(cached, ensure_ascii=False, indent=1, sort_keys=True))
        except OSError:
            pass
    _memory[(root, city, fp)] = cached
    return cached


def review_markdown(data):
    """Human checklist for automatic links; reviewers record decisions in OVERRIDES."""
    maps = lambda lat, lon, name: f'https://maps.apple.com/?ll={lat},{lon}&q={name.replace(" ", "+")}'
    lines = ['# Creator endorsement links to review', '',
             'Automatic links only boost ranking; they never create places or coordinates.',
             f'Reject or force links in `{OVERRIDES}`.', '',
             f"Linked: {len(data['entities'])} · needs review: {len(data.get('needs_review', []))} · "
             f"ambiguous: {len(data['ambiguous'])} · unmatched: {len(data['unmatched'])}", '',
             '## Linked (unreviewed)', '', '| Catalog row | Source names | Score | Basis | Map |', '|---|---|---|---|---|']
    for e in sorted(data['entities'].values(), key=lambda e: (-e['score'], e['catalog_name'])):
        names = ', '.join(sorted({o['name'] for o in e['occurrences']}))
        lines.append(f"| {e['catalog_name']} (`{e['entity_id']}`) | {names} | {e['score']} | {e['match_basis']} | "
                     f"[map]({maps(e['latitude'], e['longitude'], e['catalog_name'])}) |")
    lines += ['', '## Needs review (low confidence or no address)', '']
    lines += [f"- {r['name']} → {r['catalog_name']} (`{r['proposed_entity_id']}`)" for r in data.get('needs_review', [])]
    lines += ['', '## Ambiguous (several far-apart rows)', '']
    lines += [f"- {a['name']}: {len(a['candidate_entity_ids'])} candidates" for a in data['ambiguous']]
    return '\n'.join(lines) + '\n'


if __name__ == '__main__':
    import sys
    project = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
    out = project / '.local/stage3/endorsement-review.md'
    out.write_text(review_markdown(load(project)))
    print(out)
