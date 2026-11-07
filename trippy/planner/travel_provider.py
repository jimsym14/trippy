"""Structured venue retrieval: a provider owns places, AI only owns taste/intent."""
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import sqlite3
from urllib.parse import quote
from .planning_contract import empty_batch


class LocalCatalogTravelProvider:
    """Offline venue retrieval from local catalog.sqlite (Overture Maps).

    Permitted local inventory; never requires network access, API credentials,
    or paid billing. Only returns records satisfying policy gates with usable
    name and coordinates.

    Candidates are ordered by a deterministic suitability score
    (candidate_quality.inventory_score) plus any creator endorsement from the
    private video source pack (endorsements.py). The score is exposed as a
    ``quality:NN`` tag for the scheduler; it is not a rating.
    """
    name = 'local_catalog'
    # Extra candidates beyond the task target let the scheduler group each
    # day geographically instead of taking whatever happens to be first.
    POOL_FACTOR = 4
    MAX_POOL = 48
    # Short trips still need nearby options around whichever place anchors a day.
    MIN_POOL = 24
    # At most this many pool members per ~1 km cell, so every part of the
    # city that a day may be anchored in has nearby options.
    PER_CELL = 3

    def __init__(self, root):
        self.root = Path(root)

    def discover(self, task, brief):
        from .candidate_quality import FAMILY_SCOPE, inventory_score, row_themes, theme_boost
        from .search_intent import themes_in
        from .endorsements import load as load_endorsements, name_key
        from .plan_engine import key

        path = self.root / '.local/catalog.sqlite'
        if not path.is_file():
            return empty_batch()
        destination = brief.get('destination', '')
        city = 'Barcelona' if destination.casefold() in {'barcelona', 'βαρκελώνη', 'βαρκελωνη'} else destination
        category = task.get('category', 'attraction')
        target = task.get('target', 6)
        pool_size = min(max(target * self.POOL_FACTOR, self.MIN_POOL), self.MAX_POOL)
        area = (task.get('area_hint') or '').strip() or None
        area_slug = key(area) if area else None
        families = sorted(FAMILY_SCOPE.get(category, {'sights': None}))
        # Themes requested by the user, from the AI intent or keyword fallback.
        # Free-text AI vibe tags are folded onto the same fixed vocabulary.
        from .search_intent import THEMES
        vibes = task.get('vibe_tags') or []
        wanted = {v for v in vibes if v in THEMES} | set(themes_in(' '.join(vibes)))
        endorsements = load_endorsements(self.root, city)
        endorsed = endorsements.get('entities', {})
        core = endorsements.get('core')

        with sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True) as db:
            db.row_factory = sqlite3.Row
            query = '''SELECT cs.*, sr.url AS source_url, sr.fetched_at, sp.allowed_fields
                FROM catalog_snapshots cs
                JOIN catalog_versions cv ON cv.id=cs.catalog_version_id
                JOIN geographies g ON g.id=cv.geography_id
                JOIN source_records sr ON sr.id=cs.source_id
                JOIN source_policies sp ON sp.id=sr.policy_id
                JOIN entities e ON e.id=cs.entity_id
                WHERE lower(g.name)=lower(?) AND cv.status='published' AND e.publication_status='published'
                AND sr.owner_id IS NULL AND sr.scope_key='shared' AND sr.publication_status='published'
                AND sp.status='permitted' AND sp.can_retain_raw=1 AND sp.can_use_in_prompt=1
                AND (sr.retention_until IS NULL OR julianday(sr.retention_until)>julianday('now'))
                AND (cs.operating_status IS NULL OR cs.operating_status!='permanently_closed')
                AND cs.family IN (%s)''' % ','.join('?' * len(families))
            rows = [dict(r) for r in db.execute(query, [city, *families])]

        # Free generic city layer (Wikidata fame + Wikivoyage listings), any city.
        from . import city_evidence
        layer = city_evidence.load(self.root, city, lambda: self._light_rows(path, city)) or {}
        layer_linked = layer.get('entities', {})
        core = core or layer.get('core')
        for e in layer.get('standalone', []):
            if e['family'] in families:
                rows.append(self._pseudo_row(e, city))

        # Area hints use real neighbourhood polygons when the city has them
        # (trippy.catalog.boundaries, any city). Otherwise they fall back to the
        # address/locality text, which street names can mislead (Passeig de
        # Gràcia is in Eixample); that basis is reported, never hidden.
        # Venue names are never matched ("Acción de Gracias" is not Gràcia).
        areas = []
        if area_slug:
            from trippy.catalog.boundaries import AreaIndex
            index = AreaIndex.load(self.root, city)
            areas = index.resolve(area) if index else []
        area_basis = 'boundary' if areas else 'address_text'

        def area_match(row):
            if not area_slug:
                return False
            if areas:
                return AreaIndex.contains(areas, float(row['latitude']), float(row['longitude']))
            text = key(' '.join(filter(None, [row['address'], row['locality']])))
            return area_slug in text

        scored = {}
        for row in rows:
            entry = endorsed.get(row['entity_id'])
            civic = row.get('city_evidence') or layer_linked.get(row['entity_id'])
            strength = (entry['score'] if entry else 0.0) + (civic['score'] if civic else 0.0)
            score = inventory_score(row, category, core, strength)
            if score is None:
                continue
            found = row_themes(row, entry) | set(civic['themes'] if civic else ())
            matched = found & wanted
            score = round(min(100.0, score + theme_boost(matched)), 2)
            # Crowd-sourced duplicates (same normalized name) are often
            # mislocated copies; keep only the strongest row per name.
            dedupe = name_key(row['name']) or row['entity_id']
            current = scored.get(dedupe)
            if current is None or (score, row['entity_id']) > (current[0], current[1]['entity_id']):
                scored[dedupe] = (score, row, sorted(matched))
        ranked = self._collapse_nearby(sorted(scored.values(), key=lambda pair: (-pair[0], pair[1]['entity_id'])))

        gaps = []
        local, fallback = [], []
        if area_slug:
            gaps.append(f'area_match_basis:{category}:{area}:{area_basis}')
            local = self._spread([pair for pair in ranked if area_match(pair[1])], pool_size)
            if len(local) < target:
                shortfall = target - len(local)
                gaps.append(f'area_inventory_shortfall:{category}:{area}:found_{len(local)}_of_{target}')
                taken = {pair[1]['entity_id'] for pair in local}
                fallback = [pair for pair in ranked if pair[1]['entity_id'] not in taken][:shortfall]
                if fallback:
                    gaps.append(f'area_inventory_fallback:{category}:{area}:using_{len(fallback)}_city_candidates')
        else:
            local = self._spread(ranked, pool_size)

        batch = empty_batch()
        batch['gaps'] = gaps
        for pair, is_local in [(p, True) for p in local] + [(p, False) for p in fallback]:
            civic = pair[1].get('city_evidence') or layer_linked.get(pair[1]['entity_id'])
            built = self._place(pair[1], pair[0], category, city, area, area_slug, is_local,
                                endorsed.get(pair[1]['entity_id']), pair[2], civic)
            if built is None:
                continue
            sources, place = built
            known = {s['id'] for s in batch['sources']}
            batch['sources'].extend(s for s in sources if s['id'] not in known)
            batch['places'].append(place)
        return batch

    @staticmethod
    def _light_rows(path, city):
        with sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True) as db:
            return [{'entity_id': r[0], 'name': r[1], 'family': r[2], 'latitude': float(r[3]), 'longitude': float(r[4])}
                    for r in db.execute('''SELECT cs.entity_id, cs.name, cs.family, cs.latitude, cs.longitude
                        FROM catalog_snapshots cs JOIN catalog_versions cv ON cv.id=cs.catalog_version_id
                        JOIN geographies g ON g.id=cv.geography_id
                        WHERE lower(g.name)=lower(?) AND cv.status='published' ''', (city,))]

    @staticmethod
    def _pseudo_row(e, city):
        """A notable place absent from the catalog, located by its own cited source."""
        return {'entity_id': e['entity_id'], 'name': e['name'], 'family': e['family'],
                'source_category': e['source_category'], 'confidence': 0.9,
                'latitude': e['latitude'], 'longitude': e['longitude'], 'website_url': e.get('website'),
                'source_properties': '{}', 'address': e.get('address'), 'locality': city,
                'source_url': e['sources'][0]['url'], 'fetched_at': None,
                'allowed_fields': json.dumps(['name', 'coordinates', 'category', 'address', 'website']),
                'city_evidence': e}

    @staticmethod
    def _collapse_nearby(ranked, radius_m=80, limit=600):
        """Drop a weaker candidate within ``radius_m`` whose name is contained in a stronger one's.

        Only the strongest ``limit`` candidates can reach a plan's pool, so only
        those are compared, through a ~200 m grid index.
        """
        from .candidate_quality import distance_km
        from .endorsements import name_key
        kept, cells = [], {}
        for pair in ranked[:limit]:
            row = pair[1]; lat, lon = float(row['latitude']), float(row['longitude'])
            tokens = set(name_key(row['name']).split())
            ci, cj = round(lat / 0.002), round(lon / 0.002)
            duplicate = tokens and any(
                (tokens <= other or other <= tokens) and distance_km(lat, lon, olat, olon) * 1000 <= radius_m
                for di in (-1, 0, 1) for dj in (-1, 0, 1)
                for other, olat, olon in cells.get((ci + di, cj + dj), ()) if other)
            if not duplicate:
                kept.append(pair)
                cells.setdefault((ci, cj), []).append((tokens, lat, lon))
        return kept + ranked[limit:]

    def _spread(self, ranked, size):
        """Best-first selection with a per-cell cap, then best-first fill."""
        cells, chosen, rest = {}, [], []
        for pair in ranked:
            row = pair[1]
            cell = (round(float(row['latitude']) / 0.01), round(float(row['longitude']) / 0.013))
            if cells.get(cell, 0) < self.PER_CELL and len(chosen) < size:
                cells[cell] = cells.get(cell, 0) + 1; chosen.append(pair)
            else:
                rest.append(pair)
        chosen += rest[:max(0, size - len(chosen))]
        return sorted(chosen, key=lambda pair: (-pair[0], pair[1]['entity_id']))

    @staticmethod
    def _place(record, score, category, city, area, area_slug, is_local_match, endorsement, themes=(), civic=None):
        allowed = set(json.loads(record['allowed_fields']))
        if not {'name', 'coordinates', 'category'} <= allowed:
            return None
        standalone = record.get('city_evidence') is not None
        if standalone:
            # Identity and coordinates come from the cited Wikidata/Wikivoyage entry.
            sources = [dict(s) for s in civic['sources']]
            sid = sources[0]['id']
        else:
            sid = 'catalog-' + record['entity_id']
            sources = [{'id': sid, 'url': record['source_url'], 'publisher': 'Overture Maps Foundation',
                        'type': 'catalog', 'checked_at': record['fetched_at']}]
            if civic:
                sources += [dict(s) for s in civic['sources']]
        tags = [f'quality:{int(score):02d}', *(f'theme:{t}' for t in themes)]
        if area_slug:
            tags.append(f'area:{area_slug}' if is_local_match else f'area_fallback:{area_slug}')
        description = ''
        if area:
            why = (f'Από τον τοπικό κατάλογο ({area})' if is_local_match
                   else f'Από τον γενικό κατάλογο {city} (εκτός {area})')
        else:
            why = 'Από τον τοπικό κατάλογο (Overture Maps)'
        place_source_ids = [s['id'] for s in sources]
        if civic:
            guide = next((w for w in civic['wikivoyage'] if w.get('content')), None)
            if civic['wikivoyage']:
                why = 'Προτείνεται από το Wikivoyage'
                tags.append('wikivoyage_listed')
            elif civic.get('sitelinks'):
                why = f"Γνωστό σημείο ({civic['sitelinks']} εκδόσεις Wikipedia)"
            if civic.get('sitelinks'):
                tags.append(f"notable:{civic['sitelinks']}")
            description = (f"Wikivoyage: {guide['content']}" if guide
                           else (civic.get('description') or '').strip())
            if area:
                why += f' ({area})' if is_local_match else f' (εκτός {area})'
        if endorsement:
            video_ids = []
            for occ in endorsement['occurrences']:
                url = occ.get('url') or ''
                if not url.startswith('https://'):
                    continue
                vid = 'video-' + sha256(url.encode()).hexdigest()[:16]
                if vid not in video_ids:
                    video_ids.append(vid)
                    sources.append({'id': vid, 'url': url, 'publisher': 'Travel video creator',
                                    'type': 'video', 'checked_at': None})
            place_source_ids += video_ids
            groups = endorsement.get('publisher_groups', 1)
            why = (f'Προτείνεται από {groups} δημιουργούς ταξιδιωτικών βίντεο' if groups > 1
                   else 'Προτείνεται σε ταξιδιωτικό βίντεο')
            if area:
                why += f' ({area})' if is_local_match else f' (εκτός {area})'
            opinion = next((o['opinion'] for o in endorsement['occurrences'] if o.get('opinion')), None)
            if opinion:
                description = f'Σχόλιο δημιουργού: {opinion}'
            tags.append('source_recommended')
            if endorsement.get('review_status') == 'unreviewed':
                tags.append('identity_link_unreviewed')
        place = {
            'id': record['entity_id'], 'name': record['name'], 'category': category,
            'description': description, 'why_recommended': why,
            'address': record['address'] if 'address' in allowed else None,
            'official_url': record['website_url'] if 'website' in allowed else None,
            # Coordinates come from the catalog row only, never from a video.
            'source_ids': place_source_ids,
            'coordinates': {'latitude': float(record['latitude']), 'longitude': float(record['longitude']),
                            'source_ids': [sid]},
            'identity_status': 'source_matched', 'tags': tags,
            'price': {'min': None, 'max': None, 'currency': None, 'basis': 'unknown'},
            'price_source_ids': [], 'cuisine': None, 'dietary_options': [], 'best_for': [],
            'best_time': None, 'reservation_required': None,
            'image_url': None, 'image_source_url': None, 'image_attribution': None,
            'rating': {'value': None, 'scale': None, 'platform': None, 'review_count': None},
            'average_visit_minutes': None, 'duration_basis': 'unknown'}
        return sources, place


class GoogleTravelProvider:
    """Injected transport uses the app's existing server-only Google connection.

    No transcripts, reviews, photos or model-generated coordinates. Ratings and
    weekly opening hours ride on the same Text Search call (website already puts
    it in the Enterprise tier), so they add no request.
    Search is bounded per run and receipts are reused by StageStore.
    """
    name = 'google_places'
    def __init__(self, request): self.request = request

    def discover(self, task, brief):
        category = task['category']
        terms = {'attraction':'points of interest', 'food':'restaurants', 'coffee':'cafes',
                 'museum':'museums', 'nature':'parks', 'shopping':'shops', 'bar':'bars',
                 'club':'night clubs', 'excursion':'day trip attractions'}
        # area_hint narrows the search to a neighbourhood without replacing the
        # destination.  It is an advisory signal from intent extraction only;
        # provider-generated coordinates and identities are still required.
        area = task.get('area_hint')
        if area:
            query = task.get('query') or (
                f"{terms.get(category, category)} in {area}, {brief['destination']}"
            )
        else:
            query = task.get('query') or f"{terms.get(category, category)} in {brief['destination']}"
        response = self.request('places:searchText', body={'textQuery':query, 'pageSize':min(task['target'], 12)},
            field_mask='places.id,places.displayName,places.formattedAddress,places.location,places.googleMapsUri,places.websiteUri,places.businessStatus,'
                       'places.rating,places.userRatingCount,places.regularOpeningHours,places.utcOffsetMinutes')
        if not isinstance(response, dict) or not isinstance(response.get('places', []), list):
            raise ValueError('Invalid places response')
        batch = empty_batch(); brands = []
        for row in response.get('places', [])[:task['target']]:
            if row.get('businessStatus') in {'CLOSED_PERMANENTLY','CLOSED_TEMPORARILY'}: continue
            identifier = row.get('id'); name = row.get('displayName', {}).get('text')
            # One branch per chain: "Tonnarello", "Tonnarello Pantheon" and
            # "Tonnarello San Pietro" are the same choice for a trip.
            brand = ' '.join((name or '').casefold().split())
            if brand and any(brand == b or brand.startswith(b + ' ') or b.startswith(brand + ' ') for b in brands): continue
            brands.append(brand)
            location = row.get('location') or {}
            if not identifier or not name or location.get('latitude') is None or location.get('longitude') is None: continue
            sid = 'google-'+identifier
            url = row.get('googleMapsUri') or 'https://www.google.com/maps/search/?api=1&query='+quote(name)+'&query_place_id='+quote(identifier)
            batch['sources'].append({'id':sid,'url':url,'publisher':'Google Maps','type':'maps',
                'checked_at':datetime.now(timezone.utc).isoformat()})
            batch['places'].append({'id':identifier,'name':name,'category':category,
                'description':'','why_recommended':'Επιλογή για το ταξίδι σου', 'address':row.get('formattedAddress'),
                'official_url':row.get('websiteUri'),'source_ids':[sid],
                'coordinates':{**location,'source_ids':[sid]},'identity_status':'source_matched','tags':[],
                'price':{'min':None,'max':None,'currency':None,'basis':'unknown'},'price_source_ids':[],
                'cuisine':None,'dietary_options':[],'best_for':[],'best_time':None,'reservation_required':None,
                'image_url':None,'image_source_url':None,'image_attribution':None,
                'rating':google_rating(row),
                'average_visit_minutes':None,'duration_basis':'unknown'})
            hours = hours_tag(row)
            if hours: batch['places'][-1]['tags'].append(hours)
        return batch


def google_rating(row):
    value, count = row.get('rating'), row.get('userRatingCount')
    if not isinstance(value, (int, float)) or not 0 <= value <= 5:
        return {'value':None,'scale':None,'platform':None,'review_count':None}
    return {'value':float(value),'scale':5,'platform':'Google Maps','review_count':count if isinstance(count, int) else None}


HOURS_PREFIX = 'hours:v1:'


def hours_tag(row):
    """Weekly hours as one compact tag, so they survive batch validation and caching.

    "hours:v1:<utc offset minutes>:<open day><HHMM>-<close day><HHMM>,…", days 0=Sunday
    as Google sends them; "always" for 24/7. The pipeline turns it into
    `opening_hours` on the finished plan.
    """
    periods = (row.get('regularOpeningHours') or {}).get('periods')
    if not isinstance(periods, list) or not periods: return None
    offset = row.get('utcOffsetMinutes') if isinstance(row.get('utcOffsetMinutes'), int) else ''
    parts = []
    for period in periods[:21]:
        start, end = period.get('open') or {}, period.get('close')
        if end is None and start.get('day') == 0 and not start.get('hour') and not start.get('minute'):
            return f'{HOURS_PREFIX}{offset}:always'
        try:
            parts.append('%d%02d%02d-%d%02d%02d' % (start['day'], start.get('hour', 0), start.get('minute', 0),
                                                  end['day'], end.get('hour', 0), end.get('minute', 0)))
        except (KeyError, TypeError):
            return None
    return f'{HOURS_PREFIX}{offset}:' + ','.join(parts) if parts else None


def opening_hours_from_tags(place):
    """Move a place's hours tag into `opening_hours` (periods with day/hour/minute)."""
    tags = place.get('tags') or []
    tag = next((t for t in tags if isinstance(t, str) and t.startswith(HOURS_PREFIX)), None)
    if not tag: return None
    place['tags'] = [t for t in tags if t != tag]
    offset, _, body = tag[len(HOURS_PREFIX):].partition(':')
    hours = {'source':'google','utc_offset_minutes':int(offset) if offset.lstrip('-').isdigit() else None}
    if body == 'always': hours['always_open'] = True; hours['periods'] = []; return hours
    periods = []
    for part in body.split(','):
        a, _, b = part.partition('-')
        if len(a) != 5 or len(b) != 5 or not (a + b).isdigit(): return None
        periods.append({'open':{'day':int(a[0]),'hour':int(a[1:3]),'minute':int(a[3:5])},
                        'close':{'day':int(b[0]),'hour':int(b[1:3]),'minute':int(b[3:5])}})
    hours['periods'] = periods
    return hours
