"""Strict data contract and deterministic guards; unknown facts cannot satisfy needs."""
from datetime import date, datetime
from decimal import Decimal
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Contract(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)


class Fact(Contract):
    id: str
    field: str
    value: Any
    source_url: str
    source_kind: Literal['primary', 'transcript', 'estimate']
    reviewed_on: date
    status: Literal['reviewed_source', 'verified', 'historical', 'conflict', 'unknown', 'estimate']
    scope: str = 'venue'
    valid_through: date | None = None

    @model_validator(mode='after')
    def provenance(self):
        if not self.source_url.startswith('https://'):
            raise ValueError('Fact needs HTTPS provenance')
        if self.status == 'verified' and self.source_kind != 'primary':
            raise ValueError('Transcript or estimate cannot be a verified operational fact')
        if self.valid_through is not None and self.valid_through < self.reviewed_on:
            raise ValueError('Validity cannot precede review')
        return self


class Facet(Contract):
    key: str
    value: str
    fact_ids: list[str] = Field(min_length=1)
    review: Literal['source_compared_annotation', 'proposal']


class Place(Contract):
    id: str
    name: str
    city_id: str
    timezone: str
    identity: Literal['confirmed', 'candidate', 'ambiguous']
    location: Literal['entrance_verified', 'source_point', 'unknown']
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    facts: list[Fact]
    facets: list[Facet]
    parent_id: str | None = None
    limitations: list[str] = Field(default_factory=list)

    @model_validator(mode='after')
    def consistency(self):
        from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
        try: ZoneInfo(self.timezone)
        except (ZoneInfoNotFoundError, ValueError): raise ValueError('Valid place timezone required') from None
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError('Complete coordinate pair required')
        if self.location != 'unknown' and self.latitude is None:
            raise ValueError('Location state requires a source point')
        ids = [f.id for f in self.facts]
        if len(set(ids)) != len(ids): raise ValueError('Duplicate fact ID')
        if any(not set(f.fact_ids).issubset(ids) for f in self.facets):
            raise ValueError('Facet cannot point to missing evidence')
        return self


class Need(Contract):
    facet: str
    value: str
    hard: bool = False
    scope: str = 'venue'


class Search(Contract):
    city_id: str
    needs: list[Need] = Field(default_factory=list, max_length=30)
    on_date: date | None = None
    excluded_ids: list[str] = Field(default_factory=list, max_length=500)
    limit: int = Field(default=20, ge=1, le=100)


def fact_usable(fact, *, on_date=None, hard=False, scope='venue'):
    if fact.scope != scope or fact.value is None or fact.status in {'conflict', 'unknown', 'estimate', 'historical'}:
        return False
    if hard:
        if fact.status != 'verified' or fact.source_kind != 'primary' or on_date is None:
            return False
        if not (fact.reviewed_on <= on_date and fact.valid_through is not None and on_date <= fact.valid_through):
            return False
    return True


def retrieve(places, request):
    request = Search.model_validate(request)
    results = []; unresolved = []
    for supplied in places:
        place = Place.model_validate(supplied)
        if place.city_id != request.city_id or place.id in request.excluded_ids: continue
        facts = {f.id: f for f in place.facts}; matches = []; missing = []
        for need in request.needs:
            facets = [f for f in place.facets if f.key == need.facet and f.value == need.value
                      and f.review == 'source_compared_annotation']
            supported = [f for f in facets if all(fact_usable(facts[i], on_date=request.on_date,
                         hard=need.hard, scope=need.scope) for i in f.fact_ids)]
            if supported:
                matches.append({'facet': need.facet, 'value': need.value,
                    'fact_ids': sorted({i for f in supported for i in f.fact_ids})})
            else: missing.append(need.model_dump())
        entry = {'place_id': place.id, 'name': place.name, 'matches': matches,
                 'missing': missing, 'identity': place.identity, 'location': place.location}
        if request.needs and not matches: continue
        if place.identity != 'confirmed' or any(n['hard'] for n in missing):
            entry['state'] = 'needs_research'; unresolved.append(entry); continue
        entry['state'] = 'discovery_candidate_needs_selected_trip_checks'
        results.append(entry)
    results.sort(key=lambda r: (-len(r['matches']), r['name'], r['place_id']))
    gaps = [n.model_dump() for n in request.needs if not any(
        any(m['facet'] == n.facet and m['value'] == n.value for m in r['matches']) for r in results)]
    return {'items': results[:request.limit], 'review_candidates': unresolved[:request.limit],
            'gaps': gaps, 'gap_action': 'targeted_source_research' if gaps else None,
            'scheduled': False, 'checks_executed': False,
            'limitation': 'Retrieval is discovery; a selected-trip schedule requires separate validated checks'}


class Stop(Contract):
    decision_id: str
    place_id: str
    start: datetime
    duration_minutes: int = Field(gt=0, le=1440)
    duration_basis: Literal['verified', 'estimate', 'unknown']
    locked: bool = False
    expected_locked_place_id: str | None = None
    cost_per_person: Decimal | None = Field(default=None, ge=0)
    cost_currency: str | None = None
    cost_basis: Literal['verified', 'estimate', 'unknown'] = 'unknown'
    party_size: int = Field(default=1, gt=0, le=100)
    required_fields: list[str] = Field(default_factory=lambda: ['opening_window'])


def validate_stops(places, stops, *, transfers=None, budget=None, currency='EUR'):
    """No straight-line distance masquerades as a route; checks need dated evidence."""
    indexed = {Place.model_validate(p).id: Place.model_validate(p) for p in places}
    stops = [Stop.model_validate(s) for s in stops]
    errors = []; pending = []; total = Decimal(0); costs_complete = True
    if not stops: errors.append({'code': 'empty_plan'})
    transfers = transfers or {}
    seen_decisions = set()
    from zoneinfo import ZoneInfo
    for stop in stops:
        if stop.decision_id in seen_decisions: errors.append({'decision_id': stop.decision_id, 'code': 'duplicate_decision'})
        seen_decisions.add(stop.decision_id)
        if stop.locked and stop.expected_locked_place_id != stop.place_id:
            errors.append({'decision_id': stop.decision_id, 'code': 'user_lock_changed'})
        place = indexed.get(stop.place_id)
        if place is None or place.identity != 'confirmed':
            costs_complete = False
            pending.append({'decision_id': stop.decision_id, 'code': 'canonical_identity_required'}); continue
        if place.location != 'entrance_verified':
            pending.append({'decision_id': stop.decision_id, 'code': 'entrance_check_required'})
        if stop.start.utcoffset() is None:
            errors.append({'decision_id': stop.decision_id, 'code': 'timezone_required'})
        local_start = stop.start.astimezone(ZoneInfo(place.timezone)) if stop.start.utcoffset() is not None else stop.start
        if stop.duration_basis != 'verified':
            pending.append({'decision_id': stop.decision_id, 'code': 'duration_not_verified'})
        for field in stop.required_fields:
            available = [f for f in place.facts if f.field == field and fact_usable(f,
                on_date=local_start.date(), hard=True)]
            if not available:
                pending.append({'decision_id': stop.decision_id, 'code': 'dated_field_check_required', 'field': field})
            elif field == 'opening_window':
                minute = local_start.hour*60+local_start.minute
                windows = [f.value for f in available if isinstance(f.value, dict) and
                    f.value.get('on_date') == local_start.date().isoformat() and
                    type(f.value.get('start_minute')) is int and type(f.value.get('end_minute')) is int and
                    0 <= f.value['start_minute'] < f.value['end_minute'] <= 2880]
                if not windows:
                    pending.append({'decision_id': stop.decision_id, 'code': 'structured_opening_window_required'})
                elif not any(w['start_minute'] <= minute and minute+stop.duration_minutes <= w['end_minute'] for w in windows):
                    errors.append({'decision_id': stop.decision_id, 'code': 'outside_opening_window'})
            elif field.endswith('_chain') or field.endswith('_allowed'):
                if not any(f.value is True or (isinstance(f.value, dict) and f.value.get('confirmed') is True) for f in available):
                    errors.append({'decision_id': stop.decision_id, 'code': 'required_constraint_not_satisfied', 'field': field})
        if stop.cost_per_person is None or stop.cost_basis != 'verified' or stop.cost_currency != currency:
            costs_complete = False
            pending.append({'decision_id': stop.decision_id, 'code': 'verified_cost_required'})
        else:
            prices = [f for f in place.facts if f.field == 'price_per_person' and
                      fact_usable(f, on_date=local_start.date(), hard=True)]
            matching_price = any(isinstance(f.value, dict) and f.value.get('currency') == currency and
                f.value.get('basis') == 'per_person' and str(f.value.get('amount')) == str(stop.cost_per_person) for f in prices)
            if not matching_price:
                costs_complete = False
                pending.append({'decision_id': stop.decision_id, 'code': 'price_source_match_required'})
            else: total += stop.cost_per_person*stop.party_size
    from datetime import timedelta
    for first, second in zip(stops, stops[1:]):
        if first.start.utcoffset() is None or second.start.utcoffset() is None: continue
        transfer = transfers.get((first.place_id, second.place_id))
        if not transfer or transfer.get('status') != 'verified' or transfer.get('on_date') != first.start.date().isoformat() or \
                not transfer.get('source_url', '').startswith('https://'):
            pending.append({'decision_id': second.decision_id, 'code': 'dated_route_check_required'}); continue
        if 'wheelchair_access_chain' in first.required_fields or 'wheelchair_access_chain' in second.required_fields:
            if transfer.get('step_free_verified') is not True:
                pending.append({'decision_id': second.decision_id, 'code': 'step_free_transfer_check_required'})
        minutes = transfer.get('minutes')
        if type(minutes) is not int or minutes < 0: raise ValueError('Invalid verified route duration')
        if first.start+timedelta(minutes=first.duration_minutes+minutes) > second.start:
            errors.append({'decision_id': second.decision_id, 'code': 'schedule_overlap_or_transfer_infeasible'})
    if budget is not None and costs_complete and total > Decimal(str(budget)):
        errors.append({'code': 'budget_exceeded'})
    return {'state': 'invalid' if errors else 'needs_checks' if pending else 'validated',
            'errors': errors, 'pending': pending, 'known_total': str(total),
            'cost_complete': costs_complete, 'currency': currency,
            'booked': False, 'validation_scope': 'Supplied dated evidence and selected-stop constraints only'}
