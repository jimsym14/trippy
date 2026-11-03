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
            result = {'minutes': math.ceil(distance(a,b)/1000/4*60)+10, 'method':'distance_estimate', 'verified':False}
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
    slots = [(600, 'morning', {'attraction','museum','nature','shopping','excursion'}), (780,'afternoon',{'food','coffee'}),
             (900,'afternoon',{'attraction','museum','nature','shopping'}), (1140,'evening',{'food'}), (1260,'night',{'bar','club'})]
    if brief.get('pace') in {'χαλαρός','relaxed'}: slots = [slots[0],slots[1],slots[3]]
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
        for start, period, slot_categories in slots:
            if categories and not categories & slot_categories: continue
            options = [p for p in places if p['id'] not in used and p['category'] in slot_categories and available(p,local_date)]
            options.sort(key=lambda p:(-len(set(p['tags']) & set(brief['preference_tags'])),
                distance(previous,p) if previous else 0, p['id']))
            for p in options:
                duration = p['average_visit_minutes'] or {'attraction':75,'museum':90,'nature':90,'excursion':300}.get(p['category'],60)
                leg = travel(previous,p,local_date) if previous else None
                prior_stops = [s for s in day['stops'] if clock_minutes(s['time'])<=start]
                candidate_start = max(start, max((clock_minutes(s['time'])+s['duration_minutes'] for s in prior_stops),default=start)+(math.ceil(leg['minutes']) if leg and leg['minutes'] is not None else 0))
                check = check_for(doc,p['id'],local_date)
                if check and check['status']=='confirmed' and check['opening_windows']:
                    windows = [(clock_minutes(w['start']),clock_minutes(w['end'])) for w in check['opening_windows']]
                    viable = [(max(candidate_start,a),b) for a,b in windows if max(candidate_start,a)+duration<=b]
                    if not viable: continue
                    candidate_start = min(viable)[0]
                if candidate_start+duration>1380 or any(candidate_start<clock_minutes(s['time'])+s['duration_minutes'] and candidate_start+duration>clock_minutes(s['time']) for s in day['stops']): continue
                price = money(p)
                day['stops'].append({'place_id':p['id'],'activity':p['name'],'time':f'{candidate_start//60:02d}:{candidate_start%60:02d}',
                    'duration_minutes':duration,'duration_basis':p['duration_basis'] if p['average_visit_minutes'] else 'estimate',
                    'period':period,'status':'proposed','locked':False,'source_ids':p['source_ids'],
                    'estimated_cost_per_person_eur':float(price[0]) if price and price[0]==price[1] else None,
                    'travel_time_minutes':round(leg['minutes']) if leg and leg['minutes'] is not None else None,
                    'travel_time_basis':leg['method'] if leg else None,
                    'transport_mode':brief.get('transport_mode','walking'),
                    'alternatives':[q['id'] for q in options if q['id']!=p['id']][:3]})
                used.add(p['id']); previous=p
                break
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
    scheduled_categories={indexed[s['place_id']]['category'] for d in days for s in d['stops']}
    for category in categories-scheduled_categories:
        pending.append({'code':'selected_category_unscheduled','category':category})
    if any(canonical_category(x)=='event' for x in brief['interests']+brief['preference_tags']):
        pending.append({'code':'event_time_and_location_need_review'})
    if brief.get('budget'): pending.append({'code':'budget_coverage_pending'})
    if not dates: pending.append({'code':'trip_dates_required'})
    doc['itinerary']={'days':days}
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
