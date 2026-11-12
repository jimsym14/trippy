"""Deterministic normalization, schedule composition, arithmetic and feasibility gates."""
from copy import deepcopy
from datetime import date
from decimal import Decimal
from hashlib import sha256
import json
import math
import unicodedata
from urllib.parse import urlsplit
from research_pipeline import CONTRACT_PATH, canonical_category, has_coordinates, prepare_result, trip_dates
from .planning_contract import clock_minutes, categories as planning_categories


def key(value):
    return ''.join(c for c in unicodedata.normalize('NFD', value.casefold()) if not unicodedata.combining(c)).strip()

def digest(value): return sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False).encode()).hexdigest()

def source_ok(source):
    parsed = urlsplit(source['url'])
    return parsed.scheme == 'https' and bool(parsed.hostname) and not parsed.username and not parsed.password


def merge_batches(batches, brief):
    document = json.loads(CONTRACT_PATH.read_text())
    for field, value in list(document.items()):
        if isinstance(value, list): document[field] = []
    document['trip_context'] = deepcopy(brief)
    sources, places, date_checks, conflicts = {}, {}, {}, []
    held_dates = set()
    for batch in batches:
        source_map, place_map = {}, {}
        for source in batch['sources']:
            if source['id'] in source_map: raise ValueError('Duplicate source ID in batch')
            if not source_ok(source): raise ValueError('Research source must be public HTTPS without credentials')
            sid = 'source-'+digest(source['url'])[:20]
            source_map[source['id']] = sid
            prior = sources.get(sid)
            if prior and prior['type'] != source['type']:
                conflicts.append({'field': 'source_type', 'source_id': sid})
                prior['type'] = 'conflicted'
            sources.setdefault(sid, {**source, 'id': sid})
        def ids(values):
            if any(i not in source_map for i in values): raise ValueError('Unresolved batch source reference')
            return sorted({source_map[i] for i in values})
        for supplied in batch['places']:
            if supplied['id'] in place_map: raise ValueError('Duplicate place ID in batch')
            if not supplied['source_ids']: raise ValueError('Place identity needs source evidence')
            # Name + exact address preserve different branches. Unlocated occurrences
            # retain a content identity until a selected identity check resolves them.
            identity = [key(brief['destination']), key(supplied['name']), key(supplied['address'] or ''),
                        None if supplied['address'] else supplied['coordinates']]
            pid = 'place-'+digest(identity)[:20]
            for existing in brief.get('existing_places',[]):
                if existing.get('id') and key(existing.get('name',''))==key(supplied['name']) and existing.get('address') and key(existing['address'])==key(supplied['address'] or ''):
                    pid=existing['id']; break
            place_map[supplied['id']] = pid
            p = deepcopy(supplied); p['id'] = pid; p['source_ids'] = ids(p['source_ids'])
            p['price_source_ids'] = ids(p['price_source_ids']); p['coordinates']['source_ids'] = ids(p['coordinates']['source_ids'])
            p['category'] = canonical_category(p['category'])
            rating=p['rating']
            if rating['value'] is not None and (rating['scale']!=5 or not 0<=rating['value']<=5 or not rating['platform']):
                p['rating']={'value':None,'scale':None,'platform':None,'review_count':None}
            if p['image_url'] and not p['image_source_url']: p['image_url']=None
            if has_coordinates(p) and not p['coordinates']['source_ids']: raise ValueError('Coordinates require field-level provenance')
            if (p['coordinates']['latitude'] is None) != (p['coordinates']['longitude'] is None): raise ValueError('Incomplete coordinate pair')
            if p['coordinates']['latitude'] is not None and not has_coordinates(p): raise ValueError('Coordinates outside valid range')
            price = p['price']
            if any(price[k] is not None for k in ['min','max']) and not p['price_source_ids']: raise ValueError('Price requires field-level provenance')
            if any(price[k] is not None and price[k] < 0 for k in ['min','max']): raise ValueError('Negative price')
            if price['min'] is not None and price['max'] is not None and price['min'] > price['max']: raise ValueError('Reversed price range')
            if p['average_visit_minutes'] is not None and not 1 <= p['average_visit_minutes'] <= 720: raise ValueError('Invalid visit duration')
            prior = places.get(pid)
            if prior:
                for field in ['coordinates', 'price']:
                    first, second = prior[field], p[field]
                    keys = ['latitude','longitude'] if field=='coordinates' else ['min','max','currency','basis']
                    if any(first.get(k) is not None and second.get(k) is not None and first[k] != second[k] for k in keys):
                        conflicts.append({'place_id': pid, 'field': field})
                        p['identity_status'] = 'ambiguous'
                # Missing new fields don't wipe sourced values. Genuine conflicts are
                # held above rather than choosing the latest model answer as truth.
                p['source_ids'] = sorted(set(prior['source_ids']+p['source_ids']))
                for field in ['description','why_recommended','average_visit_minutes','address','official_url','cuisine','best_time','reservation_required','image_url','image_source_url','image_attribution']:
                    if p[field] is None or (isinstance(p[field],str) and not p[field]): p[field] = prior[field]
                for field in ['tags','dietary_options','best_for']:
                    p[field] = sorted(set(prior[field]+p[field]))
                if p['rating']['value'] is None: p['rating'] = prior['rating']
                if p['average_visit_minutes']==prior['average_visit_minutes'] and supplied['average_visit_minutes'] is None:
                    p['duration_basis']=prior['duration_basis']
                if not has_coordinates(p) and has_coordinates(prior): p['coordinates'] = prior['coordinates']
                if all(p['price'][k] is None for k in ['min','max']): p['price'] = prior['price']; p['price_source_ids'] = prior['price_source_ids']
            places[pid] = p
        for check in batch['date_checks']:
            if check['entity_id'] not in place_map: raise ValueError('Date check references missing place')
            c = deepcopy(check); c['entity_id'] = place_map[c['entity_id']]; c['source_ids'] = ids(c['source_ids'])
            for window in c['opening_windows']:
                if clock_minutes(window['start']) >= clock_minutes(window['end']): raise ValueError('Invalid opening window')
            if c['local_date'] not in trip_dates(brief): raise ValueError('Date check outside the trip')
            c['id'] = c['entity_id']+'|'+c['local_date']
            if c['status'] in {'confirmed','closed'} and (not c['checked_at'] or not c['source_ids'] or
                not all(sources[s]['type']=='primary' for s in c['source_ids'])):
                c['status'] = 'candidate'
            prior = date_checks.get(c['id'])
            if prior and prior['status']=='closed' and c['status'] not in {'closed','confirmed'}:
                c=prior
            if prior and prior['status'] != c['status'] and {prior['status'],c['status']} <= {'confirmed','closed'}:
                c['status'] = 'candidate'; c['opening_windows'] = []
                conflicts.append({'place_id': c['entity_id'], 'field': 'date_check', 'date': c['local_date']})
            if prior and prior['status']=='confirmed' and c['status']=='confirmed' and prior['opening_windows'] != c['opening_windows']:
                conflicts.append({'place_id': c['entity_id'], 'field': 'opening_windows', 'date': c['local_date']})
                held_dates.add(c['id'])
            if any(x.get('field')=='date_check' and x.get('place_id')==c['entity_id'] and x.get('date')==c['local_date'] for x in conflicts):
                held_dates.add(c['id'])
            if c['id'] in held_dates: c['status']='candidate'; c['opening_windows']=[]
            date_checks[c['id']] = c
        for field in ['constraint_checks','calendar_checks','ticket_options','transport_options','events']:
            for row in batch[field]:
                row = deepcopy(row); row['source_ids'] = ids(row['source_ids'])
                for entity_field in ['entity_id','place_id']:
                    if row.get(entity_field):
                        if row[entity_field] not in place_map: raise ValueError('Unresolved '+entity_field)
                        row[entity_field] = place_map[row[entity_field]]
                if 'id' in row: row['id'] = field+'-'+digest(row)[:20]
                if row not in document.setdefault(field, []): document[field].append(row)
        document['overview']['seasonal_notes'] += [n for n in batch['seasonal_notes'] if n not in document['overview']['seasonal_notes']]
        document['warnings'] += [{'id':'gap-'+digest(g)[:20], 'severity':'medium', 'message':g} for g in batch['gaps']]
    # A later batch cannot erase an earlier contradiction by repeating one side.
    for conflict in conflicts:
        if conflict.get('field') in {'coordinates','price'}: places[conflict['place_id']]['identity_status']='ambiguous'
    for check in date_checks.values():
        if check['status'] in {'confirmed','closed'} and not all(sources[s]['type']=='primary' for s in check['source_ids']):
            check['status']='candidate'
    document['sources'] = sorted(sources.values(), key=lambda x:x['id'])
    document['places'] = sorted(places.values(), key=lambda x:x['id'])
    document['date_checks'] = sorted(date_checks.values(), key=lambda x:x['id'])
    document['evidence_conflicts'] = conflicts
    return document


def distance(a, b):
    r = math.pi/180
    lat1, lat2 = a['coordinates']['latitude']*r, b['coordinates']['latitude']*r
    dlat = lat2-lat1; dlon = (b['coordinates']['longitude']-a['coordinates']['longitude'])*r
    return 6371000*2*math.asin(min(1,math.sqrt(math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2)))


def check_for(doc, pid, local_date):
    return next((c for c in doc['date_checks'] if c['entity_id']==pid and c['local_date']==local_date), None)


def requirement_supported(doc, pid, requirement, local_date):
    sources = {s['id']:s for s in doc['sources']}
    checks = [c for c in doc.get('constraint_checks',[]) if c['entity_id']==pid
        and key(c['requirement'])==key(requirement) and c['local_date']==local_date
        and c['checked_at'] and c['source_ids'] and all(sources[s]['type']=='primary' for s in c['source_ids'])]
    # Contradictory primary observations require review; a positive answer alone
    # must not override a documented incompatibility.
    return any(c['status']=='supported' for c in checks) and not any(c['status']=='unsupported' for c in checks)


def money(place):
    p = place['price']
    if p['currency'] != 'EUR' or p['basis'] not in {'per_person', 'adult_standard'}: return None
    if p['min'] is None or p['max'] is None: return None
    return Decimal(str(p['min'])), Decimal(str(p['max']))


# Walking legs longer than this are only used when nothing closer fits.
MAX_PREFERRED_LEG_METERS = 2200
# Each kilometre from the previous stop costs this many quality points, so a
# slightly weaker nearby place beats a stronger one across the city.
DISTANCE_PENALTY_PER_KM = 8


def quality(place):
    """Inventory suitability from a provider ``quality:NN`` tag (not a rating)."""
    for tag in place.get('tags', []):
        if tag.startswith('quality:'):
            try: return int(tag.split(':', 1)[1])
            except ValueError: return 0
    return 0


def asked_for(p):
    """Catalog places carry "theme:x" only for themes the traveller asked for (beach, art…)."""
    return any(t.startswith('theme:') for t in p.get('tags', []))


# Unpicked saves ("ideas") in one day's sightseeing at most: a personal touch, not a day of random saves.
IDEAS_PER_DAY = 2


def is_idea(p):
    """A save the traveller didn't pick: personal, but not chosen for this trip."""
    return 0 < (p.get('personal_priority') or 0) <= 50 and 'source:community' not in p.get('tags', [])


def idea_bonus(p):
    """Quality points for what backs an unpicked save: each extra video, and something written about it (a summary
    or tips). Capped at 24 (three kilometres of walking at DISTANCE_PENALTY_PER_KM), and half again for food and
    drink, where a place the traveller saved and has notes on is the tested choice. Nothing for community-only;
    a bare save takes some back (below)."""
    if not is_idea(p): return 0
    # A bare save (nothing written, one source) gives back half of what its priority adds to strength (areas.strength
    # counts 120 × priority / 100): saving it alone doesn't make it better than a well-rated neighbour.
    if not (p.get('description') or '').strip() and len(p.get('library_node_ids', [])) <= 1:
        return -0.6 * (p.get('personal_priority') or 0)
    evidence = min(2, max(0, len(p.get('library_node_ids', [])) - 1)) * 6 + (12 if (p.get('description') or '').strip() else 0)
    return min(24, evidence) * (1.5 if p.get('category') in {'food', 'coffee', 'bar'} else 1)


def slot_rank(p, previous, brief, centers=(), trip_centers=(), elsewhere=False, home=None):
    """Deterministic order for one slot.

    The day's areas come first: a place outside them waits for its own day.
    Within them, saved pins and explicit preference tags stay authoritative,
    then strength (quality, fame, rating) against distance from the previous
    stop (or the area's centre for the day's first stop).
    """
    from .areas import in_day_area, outside_metres, strength
    meters = distance(previous, p) if previous else 0
    inside = in_day_area(p, centers)
    # A saved place leads only on its own area's day when another day goes there;
    # a saved place outside every planned area keeps its priority on any day.
    personal = p.get('personal_priority', 0) if inside or not in_day_area(p, trip_centers) else 0
    # Only what the traveller chose (picked, pinned, saved, noted: over 50) leads outright. An unpicked save or a
    # community video competes on strength (which counts its priority) plus a small, capped evidence bonus.
    lead = personal if personal > 50 else 0
    # Leaving the day's areas costs like extra walking, so the day stays in them
    # without forcing a long leg to a far corner of a big area.
    # Evenings drift towards the base, so the walk home stays short.
    homeward = 0.6 * distance(home, p) if home else 0
    # A place in an area planned for another day waits for that day.
    return (elsewhere, -lead, -len(set(p['tags']) & set(brief['preference_tags'])),
            -p.get('judge_score', 0.0), meters > MAX_PREFERRED_LEG_METERS,
            -(quality(p) + strength(p) + idea_bonus(p) + 20 * sum(t.startswith('theme:') for t in p.get('tags', [])) - DISTANCE_PENALTY_PER_KM * (meters + (0 if asked_for(p) else outside_metres(p, centers)) + homeward) / 1000), p['id'])


def visit_minutes(p):
    """Sourced duration, else an estimate by what the place is (see visits.py)."""
    from .visits import minutes
    return minutes(p)


# Visits per day by pace; a quick stop (fountain, square) counts half.
DAY_VISITS = {'relaxed': 3.5, 'balanced': 6, 'speedrun': 9}


# Getting from one saved sight to the next, on top of its visit.
PIN_TRAVEL_MINUTES = 25


def assign_pins(places, dates, brief, *, area_plan, area_of, area_by_id, base_place, grouped, pace, visits, members_of=None,
                sight_hours=(570, 1140)):
    """date for each saved sight (personal priority over 50), before the days are filled.

    Its own area's day when that day has room, else the day whose planned areas (or pins) are nearest; the
    strongest sights choose first. A day's room is its sightseeing hours less lunch and a coffee, each pin
    costing its visit (the whole group's for a group lead) and the way there; an arrival afternoon has less,
    a departure morning takes only what is near the stay. A saved sight inside a group (the Sistine Chapel in
    the Vatican Museums) brings its group's lead. Pins with no room anywhere are left to the normal fill."""
    from .areas import fame
    from .visits import group_minutes, quick, closes_by
    if not dates: return {}
    members_of = members_of or {}
    times = brief.get('date_range') or {}
    first, last = sight_hours   # the trip's own sightseeing hours (friends out at night stop earlier)
    def window(i):
        start = clock_minutes(times['arrival_time']) + 90 if i == 0 and times.get('arrival_time') else first
        end = min(last, clock_minutes(times['departure_time']) - 180) if i == len(dates) - 1 and times.get('departure_time') else last
        return max(first, start), end
    meals = 105   # lunch and a coffee break
    room = {d: max(0, window(i)[1] - window(i)[0] - meals) for i, d in enumerate(dates)}
    # The day's visit budget too (a quick stop counts half), in proportion to its hours.
    visits_left = {d: DAY_VISITS[pace] * max(0, window(i)[1] - window(i)[0]) / max(1, last - first) for i, d in enumerate(dates)}
    departure_day = dates[-1] if len(dates) > 1 and times.get('departure_time') else None
    points = {d: [(area_by_id[a]['latitude'], area_by_id[a]['longitude']) for a in area_plan.get(d, [])] for d in dates}
    area_day = {a: d for d, ids in area_plan.items() for a in ids}
    lead_of = {m['id']: lead for lead, members in members_of.items() for m in members}
    by_id = {p['id']: p for p in places}
    saved = [p for p in places if (p.get('personal_priority') or 0) > 50 and p['category'] in visits and has_coordinates(p)]
    pins = {}
    for p in saved:
        lead = by_id.get(lead_of.get(p['id'], p['id']))
        if lead is not None and lead['id'] not in grouped: pins[lead['id']] = lead
    # Most famous first. A pin the city data knows nothing about (no Wikipedia count: "Colosseum" saved from a
    # list) ranks with the trip's typical pin, not last.
    known = sorted(fame(p) for p in pins.values() if fame(p))
    typical = known[len(known) // 2] if known else 0
    out = {}
    for p in sorted(pins.values(), key=lambda p: (-(fame(p) or typical), p['id'])):
        cost = (group_minutes(p, members_of[p['id']]) if p['id'] in members_of else visit_minutes(p)) + PIN_TRAVEL_MINUTES
        weight = 0.5 if quick(p) and p['id'] not in members_of else 1
        def fits(d):
            if room[d] < cost or visits_left[d] < weight: return False
            # Open long enough after the day starts (ruins close at dusk in winter; an arrival afternoon is short).
            begin, _ = window(dates.index(d))
            if begin + 105 + cost > closes_by(p, int(d[5:7])) and begin > 600: return False
            return d != departure_day or (base_place is not None and distance(base_place, p) < 1800)
        def far(d):
            pts = points[d]
            if not pts: return 9e9
            return min(distance({'coordinates': {'latitude': a, 'longitude': b}}, p) for a, b in pts)
        own = area_day.get(area_of.get(p['id']))
        choice = own if own and fits(own) else min((d for d in dates if fits(d)), key=lambda d: (far(d), d), default=None)
        if choice is None: continue
        out[p['id']] = choice; room[choice] -= cost; visits_left[choice] -= weight
        points[choice].append((p['coordinates']['latitude'], p['coordinates']['longitude']))
    return out


def compose_plan(document, brief, *, route_provider=None):
    doc = deepcopy(document)
    days, used, pending, routes = [], set(), [], []
    indexed = {p['id']:p for p in doc['places']}
    excluded = set(brief['excluded_place_ids'])
    hard = brief['dietary_needs']+brief['mobility_requirements']
    categories = set(planning_categories(brief)) - {'event'}
    places = [p for p in doc['places'] if p['id'] not in excluded and has_coordinates(p) and p['identity_status']=='source_matched']
    conflicts = {c.get('place_id') for c in doc['evidence_conflicts']}
    places = [p for p in places if p['id'] not in conflicts]
    route_cache = {}
    def travel(a, b, local_date):
        cache_key = (a['id'],b['id'],local_date,brief.get('transport_mode','walking'))
        if cache_key in route_cache: return route_cache[cache_key]
        result = None
        if not has_coordinates(a) or not has_coordinates(b):
            return {'minutes':None,'method':'missing_coordinates','verified':False,'from_place_id':a['id'],'to_place_id':b['id'],'date':local_date}
        if route_provider:
            try: result = route_provider(a, b, local_date, brief.get('transport_mode','walking'))
            except Exception: result = None
            if result is not None and (not isinstance(result,dict) or type(result.get('minutes')) not in (int,float)
                or not math.isfinite(result['minutes']) or result['minutes']<0 or not result.get('method')):
                raise ValueError('Invalid route provider result')
        if result is None:
            metres = distance(a,b)
            if metres > 2500:
                # Nobody walks 6 km between villages or across a capital: past
                # 2.5 km assume a ride (car, taxi or transit) at ~25 km/h door to door.
                result = {'minutes': math.ceil(metres/1000/25*60)+12, 'method':'ride_estimate', 'verified':False}
            else:
                # Next door is a short walk: less buffer for finding the way.
                result = {'minutes': math.ceil(metres/1000/4*60)+(5 if metres < 1000 else 10), 'method':'distance_estimate', 'verified':False}
        result = {**result,'from_place_id':a['id'],'to_place_id':b['id'],'date':local_date}
        route_cache[cache_key]=result; routes.append(result)
        return result
    def available(p, local_date):
        c = check_for(doc,p['id'],local_date)
        if c and c['status']=='closed': return False
        # Dietary checks apply to consumption; mobility applies to every stop.
        requirements = brief['mobility_requirements'] + (brief['dietary_needs'] if p['category'] in {'food','coffee','bar'} else [])
        return all(requirement_supported(doc,p['id'],r,local_date) for r in requirements)
    dates = trip_dates(brief)
    visits = {'attraction','museum','nature','shopping','excursion'}
    # (start, period, categories, end of the window or None for a single stop).
    # Sight windows are filled with as many visits as fit, like a real day:
    # morning until lunch, early afternoon until a coffee break, late afternoon
    # until dinner. Lunch and dinner are food only; coffee is a break.
    pace = 'relaxed' if brief.get('pace') in {'χαλαρός','relaxed'} else 'speedrun' if brief.get('pace') == 'speedrun' else 'balanced'
    # The coffee break sits inside the afternoon window, once the clock passes 16:00.
    slots = {
        'relaxed':  [(630,'morning',visits,780), (780,'afternoon',{'food'},None), (900,'afternoon',visits,1080),
                     (1170,'evening',{'food'},None), (1290,'night',{'bar','club'},None)],
        'balanced': [(570,'morning',visits,780), (780,'afternoon',{'food'},None), (870,'afternoon',visits,1140),
                     (1170,'evening',{'food'},None), (1290,'night',{'bar','club'},None)],
        'speedrun': [(540,'morning',visits,780), (780,'afternoon',{'food'},None), (840,'afternoon',visits,1170),
                     (1170,'evening',{'food'},None), (1290,'night',{'bar','club'},None)],
    }[pace]
    # Who travels changes the clock, as real itineraries do: friends out for the
    # night start later, take an aperitivo before a late dinner and go out after
    # it (clubs past midnight); families eat early and skip the late bars.
    group = str((brief.get('travelers') or {}).get('group') or '').casefold()
    nightlife = bool(categories & {'bar', 'club'})
    if group in {'friends', 'φίλοι'} and nightlife:
        slots = [(600 if x[0] == 570 else x[0], x[1], x[2], 1110 if x[3] == 1140 else x[3]) for x in slots if x[1] not in {'evening', 'night'}]
        slots += [(1110,'evening',{'bar'},None), (1230,'evening',{'food'},None), (1335,'night',{'bar'},None)]
        if 'club' in categories: slots.append((1420,'night',{'club'},None))  # times stay before midnight in the plan format
    elif group in {'family', 'οικογένεια'}:
        slots = [(1140,'evening',{'food'},None) if x[1] == 'evening' else x for x in slots if x[1] != 'night']
        if pace == 'balanced': slots = [(x[0], x[1], x[2], 1080 if x[3] == 1140 else x[3]) for x in slots]
    speedrun = pace == 'speedrun'
    from .visits import groups as visit_groups, group_minutes, quick, closes_by
    from .areas import strength as area_strength, in_day_area, fame as area_fame
    # Sights Wikidata links (part of / located in) and that stand together are one visit.
    linked = visit_groups(places, area_strength)
    members_of = {lead: [indexed[i] for i in ids] for lead, ids in linked.items()}
    grouped = {i for ids in linked.values() for i in ids}
    # Filler sights must be worth the walk: a fraction of the city's best, so weak
    # parks and office towers don't pad a day (saved and asked-for places always count).
    best_visit = max((area_strength(p) for p in places if p['category'] in visits), default=0)
    floor = min(15, 0.2 * best_visit)
    covered_themes = set()
    def worth(p):
        # What the traveller chose always counts; an unpicked save counts when something is written about it
        # (a summary or tips from its video), else it needs the same strength as any other filler.
        if (p.get('personal_priority') or 0) > 50: return True
        if is_idea(p) and (p.get('description') or '').strip(): return True
        return area_strength(p) >= (floor / 2 if asked_for(p) else floor)
    # Areas first: each day gets one or two neighbouring areas, starting from the base.
    from .areas import cluster, assign
    base = brief.get('base') if isinstance(brief.get('base'), dict) and brief['base'].get('latitude') is not None else None
    times_all = brief.get('date_range') or {}
    late_arrival = bool(times_all.get('arrival_time')) and clock_minutes(times_all['arrival_time']) >= 12*60
    early_departure = bool(times_all.get('departure_time')) and clock_minutes(times_all['departure_time']) <= 17*60
    areas = cluster(places, brief['preference_tags'])
    # A short departure morning only has time for something by the base, so it gets no area of its own.
    area_dates = dates[:-1] if early_departure and len(dates) > 1 else dates
    area_plan, uncovered = assign(areas, area_dates, base=base, partial_first=late_arrival)
    area_by_id = {a['id']: a for a in areas}
    trip_centers = [(area_by_id[a]['latitude'], area_by_id[a]['longitude']) for ids in area_plan.values() for a in ids]
    area_of = {pid: a['id'] for a in areas for pid in a['place_ids']}
    area_day = {a: d for d, ids in area_plan.items() for a in ids}
    base_place = {'id':'base','name':base.get('name') or 'Base','coordinates':{'latitude':base['latitude'],'longitude':base['longitude']}} if base else None
    # Saved sights get a day before anything else is chosen, so a pin never loses its place to a filler.
    pin_day = assign_pins(places, dates, brief, area_plan=area_plan, area_of=area_of, area_by_id=area_by_id,
                          base_place=base_place, grouped=grouped, pace=pace, visits=visits, members_of=members_of,
                          sight_hours=(min(x[0] for x in slots if x[3]), max(x[3] for x in slots if x[3])))
    for day_number, local_date in enumerate(dates,1):
        day = {'day':day_number,'date':local_date,'theme':'Η ημέρα σου','stops':[], 'alternative':'',
               'flex_time':'Οι ώρες είναι προτάσεις· κράτησε χρόνο για διαλείμματα.',
               'estimated_day_cost_per_person_eur':{'min':None,'max':None}}
        locks = [x for x in brief['locked_stops'] if x['date']==local_date]
        for lock in locks:
            p = indexed.get(lock['place_id'])
            if not p or p['id'] in excluded: raise ValueError('Lock references unknown/excluded place')
            day['stops'].append({'place_id':p['id'],'activity':p['name'],'time':lock['time'],
                'duration_minutes':lock['duration_minutes'],'duration_basis':'user_input','period':'locked',
                'locked':True,'status':'proposed','source_ids':p['source_ids'],'estimated_cost_per_person_eur':None,
                'travel_time_minutes':None})
            used.add(p['id'])
        previous = None
        # Arrival/departure times: free after landing (+90 min to the stay),
        # and stop 3 h before a departure.
        times = brief.get('date_range') or {}
        earliest = clock_minutes(times['arrival_time'])+90 if times.get('arrival_time') and day_number==1 else 0
        latest = clock_minutes(times['departure_time'])-180 if times.get('departure_time') and day_number==len(dates) else 1380
        day['areas'] = area_plan.get(local_date, [])
        centers = [(area_by_id[a]['latitude'], area_by_id[a]['longitude']) for a in day['areas']]
        area_anchor = {'id':'area','coordinates':{'latitude':centers[0][0],'longitude':centers[0][1]}} if centers else None
        last_day = day_number == len(dates) and len(dates) > 1 and bool(times.get('departure_time'))
        month = int(local_date[5:7])
        day_slots = list(slots)
        if last_day and latest - 540 >= 90:
            # Departure morning: breakfast near the base, then whatever fits close by.
            day_slots = [(540,'morning',{'coffee'},None), (585,'morning',visits,latest)] + [x for x in slots if x[0] >= latest]
        state = {'budget': DAY_VISITS[pace], 'previous': None, 'coffee': False, 'ideas': 0}

        def last_end(before):
            ends = [clock_minutes(s['time'])+s['duration_minutes'] for s in day['stops'] if clock_minutes(s['time']) <= before]
            return max(ends, default=None)

        def place(slot_categories, start, window_end, period, home):
            """Put the best fitting place of these categories at the next free moment; True if placed."""
            fill = window_end is not None
            previous = state['previous']
            # Sights are a walk apart. When a window would otherwise stay empty (the day's area had one sight in it),
            # one ride to the best sight still unseen beats an afternoon with nothing in it.
            reaches = (1600, 6500) if fill and not last_day else (1600,)   # a departure day stays close: no ride before a flight
            for reach in reaches:
                if reach > 1600:
                    free_from = max(start, last_end(window_end) or start)
                    if free_from + 75 > window_end: break
                # A saved sight given to a later day waits for it; one whose day has passed is fair game again.
                options = [p for p in places if p['id'] not in used and p['id'] not in grouped
                           and p['category'] in slot_categories and available(p,local_date)
                           and (pin_day.get(p['id']) or '') <= local_date]
                def mine(p): return pin_day.get(p['id']) == local_date
                if fill:
                    options = [p for p in options if worth(p) and (not is_idea(p) or state['ideas'] < IDEAS_PER_DAY)]
                    # A ride is only for a sight worth riding to: one of the city's stronger ones, never a filler.
                    if reach > 1600:
                        options = [p for p in options if p.get('personal_priority') or area_strength(p) >= 0.25 * best_visit]
                    if last_day and base_place:
                        # Departure morning: anything still unseen close to the base.
                        options = [p for p in options if mine(p) or (distance(base_place, p) < 1800 and visit_minutes(p) <= 60)]
                    else:
                        # A place in an area planned for another day waits for that day, and the
                        # next sight is a walk away: no cross-town hop for one more stop.
                        # Measured from the last sight: lunch somewhere else doesn't move the day.
                        here = state.get('visit') or previous or area_anchor or base_place
                        # Areas of earlier days are open again: what's left there is fair filler.
                        # Today's saved sights go wherever they are: the day was given to them.
                        options = [p for p in options if mine(p) or (area_day.get(area_of.get(p['id'])) or '') <= local_date
                                   and (not here or distance(here, p) < reach
                                        or (p.get('personal_priority') and centers and in_day_area(p, centers) and distance(here, p) < 2400))]
                def rank(p):
                    r = slot_rank(p, previous or area_anchor or base_place, brief, centers, trip_centers,
                                  elsewhere=not mine(p) and area_day.get(area_of.get(p['id'])) not in (None, local_date), home=home)
                    # Mornings start with the long visits (big museums, ruins): fresh legs, open doors.
                    # A theme the traveller asked for (beach, seafood) gets its first stop early.
                    fresh = (any(t.startswith('theme:') and t not in covered_themes for t in p.get('tags', []))
                             and (not previous or distance(previous, p) < 1200))
                    long_first = 0 if period == 'morning' and fill and (group_minutes(p, members_of[p['id']]) if p['id'] in members_of else visit_minutes(p)) >= 90 else 1
                    # A meal or a drink is a short walk from where the day is.
                    near = 0 if fill or not previous else int(distance(previous, p) > 1200)
                    # Today's saved sights first, nearest first among them; then everything else as before.
                    # Among them: what closes first, then the more famous (St Peter's before its square), then the nearest.
                    return (not mine(p), closes_by(p, month) if mine(p) else 0, -area_fame(p) if mine(p) else 0, r[0], min(r[1], -50) if fresh else r[1], near, long_first) + r[2:]
                if not fill and start == 540 and last_day and base_place:
                    # Breakfast before the airport is round the corner from the base.
                    options = [p for p in options if distance(base_place, p) < 1500]
                options.sort(key=rank)
                for p in options:
                    members = [m for m in members_of.get(p['id'], []) if m['id'] not in used]
                    duration = group_minutes(p, members) if members else visit_minutes(p)
                    if speedrun: duration = min(duration, 45 if not members else 90)
                    # The day starts at the base: the first stop carries the trip from there.
                    leg = travel(previous,p,local_date) if previous else (travel(base_place,p,local_date) if base_place else None)
                    # ...and never more than half an hour away from where the day is. A sight a walk from the last
                    # sight can still be far from where lunch was: past 40 minutes it isn't worth it either.
                    if (fill and previous and leg and leg['minutes'] is not None and not p.get('personal_priority')
                            and leg['minutes'] > (30 if reach > 1600 else 40)): continue
                    # The next free moment: after everything placed that starts before this
                    # window ends (a single stop also waits for a morning visit running late).
                    ended = last_end(window_end if fill else start + 180)
                    candidate_start = max(start, ended + (math.ceil(leg['minutes']) if leg and leg['minutes'] is not None else 0)) if ended is not None else start
                    check = check_for(doc,p['id'],local_date)
                    if check and check['status']=='confirmed' and check['opening_windows']:
                        windows = [(clock_minutes(w['start']),clock_minutes(w['end'])) for w in check['opening_windows']]
                        viable = [(max(candidate_start,a),b) for a,b in windows if max(candidate_start,a)+duration<=b]
                        if not viable: continue
                        candidate_start = min(viable)[0]
                    candidate_start = max(candidate_start, earliest)
                    # Meals stay at meal times: lunch by 15:30, dinner by 22:00; coffee by 17:30.
                    if p['category']=='food' and not fill and candidate_start > start+150: continue
                    # An aperitivo is before dinner, not after a long afternoon visit.
                    if p['category']=='bar' and start == 1110 and candidate_start > 1170: continue
                    if p['category']=='coffee' and not fill and candidate_start > max(start, 1050) and start != 540: continue
                    if fill:
                        # No new visit starts in the last 20 minutes of a window.
                        if candidate_start > window_end - 20: continue
                        # A window may run over by a quarter hour; a big visit never squeezes into its end.
                        # Lunch can wait for a long morning visit (Italy and Spain lunch at two).
                        # A site that closes at dusk (ruins in winter) can push it to half past two.
                        overrun = (90 if closes_by(p, month) < 1100 else 60) if period == 'morning' else 15
                        if candidate_start + duration > window_end + overrun: continue
                        # Unknown hours: open-air sites end by dusk, museums by early evening.
                        if not (check and check['status']=='confirmed') and candidate_start + duration > closes_by(p, month): continue
                    day_end = 1650 if p['category'] in {'bar','club'} else 1380
                    if candidate_start+duration > min(day_end, latest if latest < 1380 else day_end): continue
                    if any(candidate_start<clock_minutes(s['time'])+s['duration_minutes'] and candidate_start+duration>clock_minutes(s['time']) for s in day['stops']): continue
                    price = money(p)
                    day['stops'].append({'place_id':p['id'],'activity':p['name'],'time':f'{candidate_start//60:02d}:{candidate_start%60:02d}',
                        'duration_minutes':duration,'duration_basis':p['duration_basis'] if p['average_visit_minutes'] else 'estimate',
                        'period':period,'status':'proposed','locked':False,'source_ids':p['source_ids'],
                        'estimated_cost_per_person_eur':float(price[0]) if price and price[0]==price[1] else None,
                        'travel_time_minutes':round(leg['minutes']) if leg and leg['minutes'] is not None else None,
                        'travel_time_basis':leg['method'] if leg else None,
                        **({'travel_from':'base'} if not previous and base_place else {}),
                        **({'includes':[m['id'] for m in members]} if members else {}),
                        'transport_mode':brief.get('transport_mode','walking'),
                        'alternatives':[q['id'] for q in options if q['id']!=p['id']][:3]})
                    used.add(p['id']); used.update(m['id'] for m in members); state['previous'] = p
                    if fill: state['visit'] = p
                    if fill and is_idea(p): state['ideas'] += 1
                    if fill: state['budget'] -= 0.5 if quick(p) and not members else 1
                    if p['category'] == 'coffee': state['coffee'] = True
                    covered_themes.update(t for t in p.get('tags', []) if t.startswith('theme:'))
                    return True
            return False

        for start, period, slot_categories, window_end in day_slots:
            # Coffee is a break, not an interest: it runs whenever cafés were found.
            if categories and not categories & slot_categories and slot_categories != {'coffee'}: continue
            fill = window_end is not None
            if fill:
                if window_end <= earliest or start >= latest: continue
            elif start < earliest - 60 or start >= latest: continue
            home = base_place if base_place and start >= 1140 else None
            # Several drinks in one evening: aperitivo, after dinner, the club.
            if not fill:
                place(slot_categories, start, None, period, home); continue
            while state['budget'] > 0:
                # A coffee break once the afternoon passes 16:00.
                ended = last_end(window_end)
                if period == 'afternoon' and not state['coffee'] and ended is not None and ended >= 960:
                    state['coffee'] = True
                    place({'coffee'}, ended, None, 'afternoon', None)
                if not place(slot_categories, start, window_end, period, home): break
        day['stops'].sort(key=lambda s:clock_minutes(s['time']))
        # Validate the final sorted sequence, including user anchors; estimated
        # routes inform drafting but never certify real walking/transit feasibility.
        for pos, stop in enumerate(day['stops']):
            p = indexed[stop['place_id']]; check = check_for(doc,p['id'],local_date)
            if not has_coordinates(p) or p['identity_status'] != 'source_matched': pending.append({'date':local_date,'place_id':p['id'],'code':'identity_or_coordinates_pending'})
            if not check or check['status'] != 'confirmed': pending.append({'date':local_date,'place_id':p['id'],'code':'opening_check_pending'})
            if check and check['status']=='closed': pending.append({'date':local_date,'place_id':p['id'],'code':'locked_place_closed'})
            if not available(p,local_date): pending.append({'date':local_date,'place_id':p['id'],'code':'hard_requirement_pending'})
            if pos:
                prior=day['stops'][pos-1]; leg=travel(indexed[prior['place_id']],p,local_date)
                if not leg.get('verified',False): pending.append({'date':local_date,'place_id':p['id'],'code':'route_preview_required'})
                if clock_minutes(prior['time'])+prior['duration_minutes']+(math.ceil(leg['minutes']) if leg['minutes'] is not None else 0) > clock_minutes(stop['time']):
                    pending.append({'date':local_date,'place_id':p['id'],'code':'time_or_route_conflict'})
        if not day['stops']: pending.append({'date':local_date,'code':'no_feasible_sourced_stops'})
        amounts = [money(indexed[s['place_id']]) for s in day['stops']]
        known = [a for a in amounts if a]
        day['known_price_subtotal_per_person_eur']={'min':float(sum((a[0] for a in known),Decimal(0))) if known else None,
            'max':float(sum((a[1] for a in known),Decimal(0))) if known else None,
            'covered_stops':len(known),'total_stops':len(amounts),'scenario':'adult_standard_not_family_quote'}
        days.append(day)
    # Saved sights that found no room are listed, each with the day that suits it, never silently dropped.
    on_plan = {i for d in days for s in d['stops'] for i in [s['place_id']] + s.get('includes', [])}
    def best_day(p):
        if pin_day.get(p['id']): return pin_day[p['id']]
        own = area_day.get(area_of.get(p['id']))
        if own: return own
        spots = [(d['date'], indexed[s['place_id']]) for d in days for s in d['stops'] if has_coordinates(indexed[s['place_id']])]
        return min(spots, key=lambda x: distance(x[1], p))[0] if spots else (dates[0] if dates else None)
    doc['unscheduled_saved'] = [{'place_id': p['id'], 'name': p['name'], 'suggested_date': best_day(p)}
                                for p in sorted(places, key=lambda p: p['name'])
                                if (p.get('personal_priority') or 0) > 50 and p['category'] in visits and p['id'] not in on_plan]
    scheduled_categories={indexed[s['place_id']]['category'] for d in days for s in d['stops']}
    for category in categories-scheduled_categories:
        pending.append({'code':'selected_category_unscheduled','category':category})
    if any(canonical_category(x)=='event' for x in brief['interests']+brief['preference_tags']):
        pending.append({'code':'event_time_and_location_need_review'})
    if brief.get('budget'): pending.append({'code':'budget_coverage_pending'})
    if not dates: pending.append({'code':'trip_dates_required'})
    doc['itinerary']={'days':days}
    if base: doc['itinerary']['base']={'name':base.get('name') or 'Base','latitude':base['latitude'],'longitude':base['longitude'],
                                       'address':base.get('address')}
    # Area coverage: which days visit each area, and which important ones the plan skips.
    scheduled_ids={i for d in days for s in d['stops'] for i in [s['place_id']]+s.get('includes',[])}
    for area in areas:
        area['days']=[d['date'] for d in days if area['id'] in d.get('areas',[]) and any(s['place_id'] in area['place_ids'] for s in d['stops'])]
        area['planned_place_ids']=[i for i in area['place_ids'] if i in scheduled_ids]
        area['covered']=bool(area['planned_place_ids'])
    doc['areas']=areas
    adjacent={(a['place_id'],b['place_id'],d['date']) for d in days for a,b in zip(d['stops'],d['stops'][1:])}
    doc['route_previews']=[r for r in routes if (r['from_place_id'],r['to_place_id'],r['date']) in adjacent]
    doc['plan_validation']={'status':'needs_checks' if pending else 'validated' if days else 'discovery_only',
        'pending':pending,'booking_confirmed':False,'duration_estimates_explicit':True}
    known = [money(indexed[s['place_id']]) for d in days for s in d['stops']]
    priced = [a for a in known if a]
    doc['costs']['transport_and_attractions_subtotal']={'per_person_eur':None,'group_eur':None,'basis':'No complete transport/admission quote'}
    doc['costs']['known_scheduled_price_subtotal']={'min':float(sum((a[0] for a in priced),Decimal(0))) if priced else None,
        'max':float(sum((a[1] for a in priced),Decimal(0))) if priced else None,'currency':'EUR',
        'covered_stops':len(priced),'total_stops':len(known),'basis':'adult_standard_scenario','group_total_eur':None}
    doc['costs']['methodology']='Μόνο γνωστές τιμές επιλεγμένων στάσεων· ενδεικτικό σενάριο ενηλίκου. Διαμονή, μεταφορές, ελλείπουσες τιμές και εκπτώσεις δεν προσμετρώνται ως μηδέν.'
    for d in days:
        for s in d['stops']:
            p=indexed[s['place_id']]
            if p['reservation_required']:
                doc['booking_tasks'].append({'id':'booking-'+s['place_id']+'-'+d['date'],'task':'Έλεγξε και κλείσε τη θέση για '+p['name'],
                    'place_id':p['id'],'local_date':d['date'],'url':p['official_url'],'type':'booking','status':'pending',
                    'urgency_score':3,'urgency_basis':'planning_recommendation','source_ids':p['source_ids']})
    doc['overview']['summary']=f"Πρόταση για {brief['destination']}: {len(days)} ημέρες, {sum(len(d['stops']) for d in days)} στάσεις. Οι εκκρεμότητες εμφανίζονται ανά ημέρα."
    doc['map_overview']['title']=brief['destination']
    doc['map_overview']['subtitle']='Σημεία από πηγές· διαδρομές και οδηγίες στο πρόγραμμα.'
    # Readiness is coverage PLUS feasibility, not the mere presence of sections.
    doc=prepare_result(doc,brief)
    doc['delivery_status']='ready' if doc['quality_report']['status']=='ready' and doc['plan_validation']['status']=='validated' else 'partial'
    for item in pending:
        doc['warnings'].append({'id':'plan-'+digest(item)[:20],'severity':'medium','message':item['code'],**item})
    return doc
