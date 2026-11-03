"""Deterministic source-based drafts, with estimates and unmet checks explicit."""
from copy import deepcopy
from datetime import date, timedelta
from trippy.planner.dataset_reader import retrieve_activity, map_layers


def validate_trip(trip, registry):
    permitted = {'start_date', 'end_date', 'synthetic', 'activities', 'excluded_ids',
                 'locks', 'breakfast_at_stay', 'hard_requirements', 'budget_eur'}
    if not isinstance(trip, dict) or set(trip)-permitted:
        raise ValueError('Trip has unknown fields')
    result = deepcopy(trip)
    start, end = date.fromisoformat(trip['start_date']), date.fromisoformat(trip['end_date'])
    if not 0 <= (end-start).days < 14:
        raise ValueError('Trip must contain 1 to 14 days')
    if type(trip.get('synthetic', False)) is not bool:
        raise ValueError('synthetic must be boolean')
    activities = trip.get('activities', [])
    if not isinstance(activities, list) or len(activities)>14:
        raise ValueError('Bounded activity list required')
    known = {a['id'] for a in registry['activities']}
    seen = set()
    for a in activities:
        if not isinstance(a, dict) or set(a)-{'id', 'frequency'} or a.get('id') not in known or a['id'] in seen:
            raise ValueError('Unknown/duplicate activity')
        if a.get('frequency', 'once') not in {'once', 'daily'}:
            raise ValueError('Activity frequency must be once or daily')
        seen.add(a['id'])
    mode = trip.get('breakfast_at_stay')
    if mode not in {None, 'provided', 'buy_supplies', 'unknown'}:
        raise ValueError('Unknown breakfast_at_stay mode')
    if 'breakfast_at_stay' in seen and mode is None:
        raise ValueError('Breakfast at stay needs provided/buy_supplies/unknown')
    for field in ('excluded_ids', 'hard_requirements', 'locks'):
        if not isinstance(trip.get(field, []), list) or len(trip.get(field, []))>100:
            raise ValueError('Bounded list required: '+field)
    if any(not isinstance(x, str) for x in trip.get('excluded_ids', [])):
        raise ValueError('Exclusions require stable IDs')
    if any(x not in {'dietary', 'allergy', 'accessibility'} for x in trip.get('hard_requirements', [])):
        raise ValueError('Unsupported hard requirement')
    budget = trip.get('budget_eur')
    if budget is not None and (type(budget) not in {int, float} or not 0<=budget<1_000_000):
        raise ValueError('Invalid EUR budget')
    result.setdefault('synthetic', False)
    return result


def compose(compiled, trip):
    indexed = {p['id']: p for p in compiled['places']}
    exclusions = set(trip.get('excluded_ids', []))
    start, end = date.fromisoformat(trip['start_date']), date.fromisoformat(trip['end_date'])
    dates = [(start+timedelta(days=i)).isoformat() for i in range((end-start).days+1)]
    days = [{'date': d, 'stops': [], 'pending': []} for d in dates]
    requirements = trip.get('hard_requirements', [])
    for lock in trip.get('locks', []):
        if not isinstance(lock, dict) or set(lock) != {'place_id','day','start_minute','duration_minutes'}:
            raise ValueError('Lock requires place_id/day/start_minute/duration_minutes')
        if lock['place_id'] not in indexed or lock['day'] not in dates or lock['place_id'] in exclusions:
            raise ValueError('Lock is unknown or conflicts with exclusion/date')
        if (type(lock['start_minute']) is not int or type(lock['duration_minutes']) is not int or
            lock['duration_minutes']<=0 or not 0<=lock['start_minute']<1440 or
            lock['start_minute']+lock['duration_minutes']>1440):
            raise ValueError('Invalid locked window')
        day = days[dates.index(lock['day'])]
        day['stops'].append({'decision_id': 'lock:'+str(len(day['stops'])), **lock,
            'name': indexed[lock['place_id']]['name'], 'activities': [], 'locked': True,
            'duration_basis': 'user_input', 'cost_eur': None, 'state': 'needs_selected_checks',
            'pending': ['canonical_identity', 'opening_window', 'route']+requirements})

    activity_specs = trip.get('activities', [])
    mode = trip.get('breakfast_at_stay')
    if mode:
        for day in days:
            day['stops'].append({'decision_id': day['date']+':stay_breakfast', 'place_id': None,
                'name': 'Breakfast at stay', 'activities': ['breakfast_at_stay'], 'start_minute': 480,
                'duration_minutes': 30, 'duration_basis': 'estimate', 'cost_eur': None,
                'locked': False, 'state': 'stay_time_block',
                'pending': ['stay_breakfast_provision_unknown'] if mode=='unknown' else []})
    retrievals = {a['id']: retrieve_activity(compiled, a['id'], excluded_ids=exclusions)
                  for a in activity_specs if a['id'] != 'breakfast_at_stay'}
    if mode == 'buy_supplies':
        retrievals['groceries'] = retrieve_activity(compiled, 'groceries', excluded_ids=exclusions)
    once_done = set()
    for day_index, day in enumerate(days):
        cursor = 600
        specs = [a for a in activity_specs if a['id'] != 'breakfast_at_stay']
        if mode == 'buy_supplies' and day_index == 0:
            specs = [{'id': 'groceries', 'frequency': 'once'}]+specs
        for a in specs:
            activity = a['id']
            if a.get('frequency', 'once') == 'once' and activity in once_done:
                continue
            once_done.add(activity)
            if requirements:
                day['pending'].append({'activity': activity, 'code': 'hard_requirements_need_applicable_evidence',
                                       'requirements': requirements})
                continue
            results = retrievals[activity]['items']
            if not results:
                day['pending'].append({'activity': activity, 'code': 'no_reviewed_source_candidate'})
                continue
            mergeable={'coffee_break','brunch','breakfast_out','sweet_break'}
            merge_ids={s['place_id'] for s in day['stops'] if not s['locked'] and
                       s['activities'] and set(s['activities'])<=mergeable}
            chosen = next((r for r in results if activity in mergeable and r['place_id'] in merge_ids),results[0])
            # Merge only when the same occurrence supports both activities.
            existing = next((s for s in day['stops'] if s['place_id']==chosen['place_id'] and not s['locked'] and
                set(s['activities']) <= {'coffee_break','brunch','breakfast_out','sweet_break'} and
                activity in {'coffee_break','brunch','breakfast_out','sweet_break'}), None)
            if existing:
                existing['activities'].append(activity)
                existing['evidence'].extend(chosen['evidence'])
                if activity in {'brunch', 'breakfast_out'}:
                    existing['duration_minutes'] = max(existing['duration_minutes'], 60)
                    cursor = max(cursor, existing['start_minute']+existing['duration_minutes']+30)
                continue
            duration = 60 if activity in {'brunch','breakfast_out'} else 30
            # Keep user anchors fixed; search a free estimated window.
            for stop in sorted(day['stops'], key=lambda s:s['start_minute']):
                if cursor < stop['start_minute']+stop['duration_minutes'] and cursor+duration > stop['start_minute']:
                    cursor = stop['start_minute']+stop['duration_minutes']+30
            if cursor+duration>1260:
                day['pending'].append({'activity': activity, 'code': 'no_draft_window'})
                continue
            day['stops'].append({'decision_id': day['date']+':'+activity,
                'place_id': chosen['place_id'], 'name': chosen['name'], 'activities': [activity],
                'start_minute': cursor, 'duration_minutes': duration, 'duration_basis': 'estimate',
                'cost_eur': None, 'locked': False, 'state': 'source_candidate_needs_selected_checks',
                'evidence': deepcopy(chosen['evidence']), 'alternatives': deepcopy(results[1:3]),
                'pending': ['canonical_identity', 'opening_window', 'route', 'price_if_budget_required']})
            cursor += duration+30
        day['stops'].sort(key=lambda s: (s['start_minute'], s['decision_id']))
    selected = {s['place_id'] for day in days for s in day['stops'] if s['place_id']}
    errors=[]
    for day in days:
        for first, second in zip(day['stops'],day['stops'][1:]):
            if first['start_minute']+first['duration_minutes']>second['start_minute']:
                errors.append({'day': day['date'], 'code':'draft_window_overlap',
                               'decisions':[first['decision_id'],second['decision_id']]})
    pending=sum(len(day['pending'])+sum(len(s['pending']) for s in day['stops']) for day in days)
    return {'version': 1, 'trip': deepcopy(trip), 'days': days, 'retrieval': retrievals,
        'map': map_layers(compiled, selected),
        'panels': [{'place_id': p['id'], 'name': p['name'], 'source': p['source'],
                    'details': p['details'], 'tags': p['tags'], 'record_claims': p['record']['claims'],
                    'media': [], 'identity': p['identity']} for p in compiled['places'] if p['id'] in selected],
        'budget': {'requested_eur':trip.get('budget_eur'), 'known_total_eur': None,
                   'cost_complete': False, 'unknown_prices_not_zero': True},
        'validation': {'state': 'invalid_constraints' if errors else 'needs_selected_checks' if pending else 'draft_with_estimates',
            'errors': errors, 'pending_count': pending, 'dated_checks_executed': False,
            'route_feasibility_verified': False, 'duration_estimates_only': True},
        'booked': False, 'planner_ready': False,
        'limitation': 'Source-based draft; no canonical dedup, route fit, current availability or full UI rendered.'}
