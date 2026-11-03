"""Typed research batches; generation supplies evidence, the app derives the plan."""
from copy import deepcopy
import math
from research_pipeline import trip_dates, canonical_category


def obj(properties):
    return {'type': 'object', 'properties': properties, 'required': list(properties), 'additionalProperties': False}

def array(items): return {'type': 'array', 'items': items}
STR = {'type': 'string'}
TEXT = {'type': ['string', 'null']}
NUMBER = {'type': ['number', 'null']}
IDS = array(STR)
SOURCE = obj({'id': STR, 'url': STR, 'publisher': STR, 'type': STR, 'checked_at': TEXT})
PRICE = obj({'min': NUMBER, 'max': NUMBER, 'currency': TEXT, 'basis': STR})
PLACE = obj({
    'id': STR, 'name': STR, 'category': STR, 'description': STR, 'why_recommended': STR,
    'address': TEXT, 'official_url': TEXT, 'source_ids': IDS,
    'coordinates': obj({'latitude': NUMBER, 'longitude': NUMBER, 'source_ids': IDS}),
    'identity_status': {'type': 'string', 'enum': ['source_matched', 'candidate', 'ambiguous']},
    'tags': IDS, 'price': PRICE, 'price_source_ids': IDS,
    'cuisine': TEXT, 'dietary_options': IDS, 'best_for': IDS, 'best_time': TEXT,
    'reservation_required': {'type':['boolean','null']},
    'image_url': TEXT, 'image_source_url': TEXT, 'image_attribution': TEXT,
    'rating': obj({'value':NUMBER,'scale':NUMBER,'platform':TEXT,'review_count':NUMBER}),
    'average_visit_minutes': NUMBER, 'duration_basis': {'type': 'string', 'enum': ['source', 'estimate', 'unknown']},
})
CHECK = obj({'entity_id': STR, 'local_date': STR,
    'status': {'type': 'string', 'enum': ['confirmed', 'closed', 'candidate', 'not_found', 'not_checked']},
    'opening_windows': array(obj({'start': STR, 'end': STR})),
    'details': STR, 'source_ids': IDS, 'checked_at': TEXT})
CONSTRAINT = obj({'entity_id': STR, 'requirement': STR, 'local_date': STR,
    'status': {'type': 'string', 'enum': ['supported', 'unsupported', 'unknown']}, 'source_ids': IDS, 'checked_at': TEXT})
CALENDAR = obj({'date': STR, 'status': STR, 'details': STR, 'source_ids': IDS, 'checked_at': TEXT})
TICKET = obj({'id': STR, 'place_id': TEXT, 'name': STR, 'price_per_person_eur': NUMBER,
    'group_price_eur': NUMBER, 'booking_url': TEXT, 'notes': STR, 'source_ids': IDS})
TRANSPORT = obj({'id': STR, 'name': STR, 'best_for': STR, 'price': PRICE,
    'official_url': TEXT, 'source_ids': IDS, 'limitations': IDS})
EVENT = obj({'id': STR, 'name': STR, 'category': STR, 'date_start': TEXT, 'date_end': TEXT,
    'venue': TEXT, 'description': STR, 'official_url': TEXT, 'source_ids': IDS, 'confidence': STR})
BATCH_SCHEMA = obj({'sources': array(SOURCE), 'places': array(PLACE), 'date_checks': array(CHECK),
    'constraint_checks': array(CONSTRAINT), 'calendar_checks': array(CALENDAR), 'ticket_options': array(TICKET),
    'transport_options': array(TRANSPORT), 'events': array(EVENT), 'seasonal_notes': IDS, 'gaps': IDS})


def normalized_brief(supplied):
    if not isinstance(supplied, dict): raise ValueError('Trip brief must be an object')
    brief = deepcopy(supplied)
    destination = brief.get('destination')
    if not isinstance(destination, str) or not destination.strip() or len(destination) > 160:
        raise ValueError('A bounded destination is required')
    brief['destination'] = destination.strip()
    date_range=brief.get('date_range') or {}
    if not isinstance(date_range,dict): raise ValueError('Date range must be an object')
    for field in ('arrival','departure'):
        value=date_range.get(field)
        if value is not None and (not isinstance(value,str) or len(value)>10): raise ValueError('Invalid trip date')
    if date_range.get('arrival') and date_range.get('departure') and not date_range.get('dates_unknown'):
        from datetime import date
        if (date.fromisoformat(date_range['departure'])-date.fromisoformat(date_range['arrival'])).days>30:
            raise ValueError('A plan supports at most 31 days')
    dates = trip_dates(brief)
    if len(dates) > 31: raise ValueError('A plan supports at most 31 days')
    for key in ['interests', 'vibes', 'preference_tags', 'dietary_needs', 'mobility_requirements', 'excluded_place_ids']:
        values = brief.get(key, [])
        if not isinstance(values, list) or len(values) > 100 or any(not isinstance(x, str) or len(x) > 200 for x in values):
            raise ValueError('Invalid preference list: '+key)
        brief[key] = sorted(set(values))
    travelers = brief.get('travelers', {})
    if not isinstance(travelers, dict) or type(travelers.get('count', 1)) is not int or not 1 <= travelers.get('count', 1) <= 100:
        raise ValueError('Traveler count must be 1 to 100')
    brief['travelers'] = {**travelers, 'count': travelers.get('count', 1)}
    if not isinstance(brief.get('custom_instructions', ''), str) or len(brief.get('custom_instructions', '')) > 8000:
        raise ValueError('Invalid custom instructions')
    locks = brief.get('locked_stops', [])
    if not isinstance(locks, list) or len(locks) > 100: raise ValueError('Invalid locked stops')
    for lock in locks:
        if (not isinstance(lock, dict) or set(lock) != {'place_id', 'date', 'time', 'duration_minutes'}
            or not isinstance(lock['place_id'], str) or lock['date'] not in dates
            or type(lock['duration_minutes']) is not int or not 1 <= lock['duration_minutes'] <= 720):
            raise ValueError('Lock needs a valid place/date/time/duration')
        clock_minutes(lock['time'])
    brief['locked_stops'] = deepcopy(locks)
    for field in ['existing_places','existing_sources']:
        records=brief.get(field,[])
        if not isinstance(records,list) or len(records)>150 or any(not isinstance(r,dict) for r in records): raise ValueError('Invalid prior trip evidence')
        brief[field]=deepcopy(records)
    return brief


def clock_minutes(value):
    if not isinstance(value, str): raise ValueError('Expected HH:mm local time')
    parts = value.split(':')
    if len(parts) != 2 or any(len(x) != 2 or not x.isdigit() for x in parts): raise ValueError('Expected HH:mm local time')
    h, m = map(int, parts)
    if not 0 <= h <= 24 or not 0 <= m < 60 or (h == 24 and m): raise ValueError('Invalid local time')
    return h*60+m


def validate_batch(value):
    # Check every nested field against the same schema sent to the model.
    def walk(item, schema, path):
        allowed = schema['type'] if isinstance(schema['type'], list) else [schema['type']]
        typ = 'null' if item is None else 'boolean' if isinstance(item, bool) else 'object' if isinstance(item, dict) else 'array' if isinstance(item, list) else 'number' if isinstance(item, (int,float)) else 'string' if isinstance(item,str) else 'invalid'
        if typ not in allowed or (typ == 'number' and not math.isfinite(item)): raise ValueError('Invalid field: '+path)
        if 'enum' in schema and item not in schema['enum']: raise ValueError('Invalid enum: '+path)
        if typ == 'object':
            if set(item) != set(schema['properties']): raise ValueError('Missing/unknown fields: '+path)
            for k, v in item.items(): walk(v, schema['properties'][k], path+'.'+k)
        if typ == 'array':
            if len(item)>300: raise ValueError('Batch list too large: '+path)
            for v in item: walk(v, schema['items'], path+'[]')
        if typ == 'string' and len(item)>12000: raise ValueError('Batch text too large: '+path)
    walk(value, BATCH_SCHEMA, 'batch')
    return deepcopy(value)


def empty_batch():
    return {key: [] for key in BATCH_SCHEMA['properties']}


def categories(brief):
    selected = brief['interests']+brief['preference_tags']
    result = sorted({canonical_category(x) for x in selected} - {'other'})
    # Core daily choices remain available when a taste preference adds coffee,
    # nightlife or a specialist interest. Preferences are not global exclusions.
    return sorted(set(result) | {'attraction', 'food'})
