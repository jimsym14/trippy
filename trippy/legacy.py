"""Non-mutating compatibility adapters for legacy research and iOS trip exports.

Legacy facts are imported claims, never fresh evidence or published catalog.
Stable IDs are tenant/trip-scoped UUID5s; place swaps do not define slot identity.
"""

import copy
import hashlib
import json
from datetime import date
from uuid import UUID, uuid5

from research_pipeline import canonical_category
from .contracts import Candidate, Coordinate, Day, Decision, ImportedClaim, ImportedSource, NormalizedTrip, PrivatePlace


APP_STATE_KEYS = (
    "scheduleOrderByDate", "reactionsByItemID", "mapCoordinatesByPlaceID",
    "scheduleEditsByItemID", "checklistDoneIDs", "budgetEntries", "updatedAt",
)
PROTECTED_KEYS = set(APP_STATE_KEYS) | {"owner_id", "id_map", "decisions", "app_owned_state"}
LIST_KEYS = {"places", "events", "sources", "booking_tasks", "transport_options", "ticket_options",
             "calendar_checks", "date_checks", "map_views", "warnings", "assumptions"}
OBJECT_KEYS = {"overview", "map_overview", "trip_context", "costs", "itinerary"}


def document_hash(document):
    return hashlib.sha256(json.dumps(document, ensure_ascii=False, sort_keys=True, allow_nan=False).encode()).hexdigest()


def row_id(row):
    return next((str(row[key]) for key in ("id", "place_id", "event_id", "task_id")
                 if isinstance(row.get(key), (str, int)) and not isinstance(row.get(key), bool) and str(row[key])), None)


def merge_legacy_patch(foundation, patch):
    if foundation.get("schema_version") != "trippy-research-v1":
        raise ValueError("A full v1 foundation is required before applying a patch")
    merged = copy.deepcopy(foundation)
    version = patch.get("schema_version")
    if version == "trippy-research-patch-v1":
        for source_key, target in (("add_places", "places"), ("add_sources", "sources")):
            incoming = patch.get(source_key, [])
            if not isinstance(incoming, list) or any(not isinstance(row, dict) or not row_id(row) for row in incoming):
                raise ValueError("Invalid additive patch records")
            existing = merged.setdefault(target, [])
            seen = {row_id(row) for row in existing}
            for row in incoming:
                if row_id(row) not in seen:
                    existing.append(copy.deepcopy(row))
                    seen.add(row_id(row))
    elif version == "trippy-research-patch-v2":
        for operation in ("set", "replace", "upsert"):
            changes = patch.get(operation, {})
            if not isinstance(changes, dict):
                raise ValueError("Patch operations must be objects")
            for key, value in changes.items():
                if key in PROTECTED_KEYS or key not in LIST_KEYS | OBJECT_KEYS:
                    raise ValueError("Patch cannot change user ownership/state or unsupported modules")
                if operation == "upsert":
                    if key not in LIST_KEYS or not isinstance(value, list):
                        raise ValueError("Upsert requires a supported record list")
                    rows = merged.setdefault(key, [])
                    positions = {row_id(row): index for index, row in enumerate(rows) if isinstance(row, dict)}
                    incoming_ids = set()
                    for row in value:
                        if not isinstance(row, dict) or not row_id(row) or row_id(row) in incoming_ids:
                            raise ValueError("Invalid or duplicate upsert record ID")
                        incoming_ids.add(row_id(row))
                        if row_id(row) in positions:
                            rows[positions[row_id(row)]].update(copy.deepcopy(row))
                        else:
                            positions[row_id(row)] = len(rows)
                            rows.append(copy.deepcopy(row))
                else:
                    expected = list if key in LIST_KEYS else dict
                    if not isinstance(value, expected):
                        raise ValueError("Patch module has the wrong type")
                    merged[key] = copy.deepcopy(value)
    else:
        raise ValueError("Unsupported legacy patch version")
    warnings = patch.get("warnings", [])
    if not isinstance(warnings, list):
        raise ValueError("Patch warnings must be a list")
    merged["warnings"] = merged.get("warnings", []) + copy.deepcopy(warnings)
    return merged


def optional_date(value):
    if not isinstance(value, str):
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None


def normalize_legacy_trip(payload, *, owner_id, trip_key=None):
    original = copy.deepcopy(payload)
    owner_id = UUID(str(owner_id))
    native = "brief" in payload and "schema_version" not in payload
    brief = copy.deepcopy(payload.get("brief", {}) if native else payload.get("trip_context", {}))
    research = payload.get("research") if native else payload
    if research is None:
        research = {"schema_version": "trippy-research-v1", "places": [], "sources": [], "itinerary": {"days": []}}
    if isinstance(research, str):
        research = json.loads(research)
    if not isinstance(research, dict) or research.get("schema_version") != "trippy-research-v1":
        raise ValueError("Expected full v1 research or a native trip containing full v1 research")
    trip_key = str(trip_key or (payload.get("id") if native else "") or "")
    if not trip_key:
        raise ValueError("A stable trip_key is required for a standalone research import")
    trip_id = uuid5(owner_id, "legacy-trip:" + trip_key)
    id_map = {}

    def stable(key):
        identifier = uuid5(trip_id, key)
        id_map[key] = str(identifier)
        return identifier

    state = {key: copy.deepcopy(payload[key]) for key in APP_STATE_KEYS if native and key in payload}
    warnings = []
    sources = []
    source_map = {}
    for row in research.get("sources", []):
        legacy_id = row_id(row)
        if not legacy_id or legacy_id in source_map or not isinstance(row.get("url"), str):
            raise ValueError("Sources require unique IDs and URLs")
        source_map[legacy_id] = stable("source:" + legacy_id)
        sources.append(ImportedSource(id=source_map[legacy_id], legacy_id=legacy_id, url=row["url"],
                                      publisher=row.get("publisher"), checked_on=optional_date(row.get("checked_at")),
                                      legacy_fields=copy.deepcopy(row)))
    places = []
    place_map = {}
    claims = []
    for row in research.get("places", []):
        legacy_id = row_id(row)
        if not legacy_id or legacy_id in place_map or not row.get("name"):
            raise ValueError("Places require unique IDs and names")
        place_map[legacy_id] = stable("place:" + legacy_id)
        coords = row.get("coordinates") or {}
        if not isinstance(coords, dict):
            raise ValueError("Invalid coordinate object")
        known = {"id", "category", "name", "address", "coordinates", "official_url", "description", "tags"}
        category = str(row.get("category") or "other")
        places.append(PrivatePlace(id=place_map[legacy_id], legacy_id=legacy_id, name=str(row["name"]), category=category,
                                   address=row.get("address"), official_url=row.get("official_url"),
                                   coordinates=Coordinate(latitude=coords.get("latitude"), longitude=coords.get("longitude"),
                                                          status=str(coords.get("status") or "unverified")),
                                   coordinate_extensions={key: copy.deepcopy(value) for key, value in coords.items()
                                                          if key not in {"latitude", "longitude", "status"}},
                                   description=row.get("description"), tags=row.get("tags") or [],
                                   legacy_fields={key: copy.deepcopy(value) for key, value in row.items() if key not in known}))
        references = []
        for reference in row.get("source_ids", []):
            if str(reference) not in source_map:
                raise ValueError("A place references an unknown source ID")
            references.append(source_map[str(reference)])
        for key in ("price", "rating", "status_on_travel_dates", "average_visit_minutes", "reservation_required", "dietary_options"):
            if row.get(key) is not None:
                claims.append(ImportedClaim(id=stable(f"claim:{legacy_id}:{key}"), user_place_id=place_map[legacy_id],
                                            field_key=key, value=copy.deepcopy(row[key]), source_ids=references,
                                            checked_on=optional_date(row.get("checked_at"))))
    days = []
    decisions = []
    day_records = (research.get("itinerary") or {}).get("days", [])
    if not isinstance(day_records, list):
        raise ValueError("Itinerary days must be a list")
    for index, day in enumerate(day_records):
        day_key = str(day.get("date") or f"day-{index + 1}")
        day_id = stable("day:" + day_key)
        saved_order = state.get("scheduleOrderByDate", {}).get(day_key)
        days.append(Day(id=day_id, legacy_key=day_key, local_date=optional_date(day.get("date")),
                        day_number=index + 1, theme=day.get("theme"), order_locked=saved_order is not None,
                        legacy_fields={key: copy.deepcopy(value) for key, value in day.items() if key not in {"stops", "activities", "items"}}))
        stops = day.get("stops", day.get("activities", day.get("items", [])))
        if not isinstance(stops, list):
            raise ValueError("Day stops must be a list")
        base = {f"stop|{day_key}|{offset}": stop for offset, stop in enumerate(stops)}
        active_keys = list(saved_order) if saved_order is not None else list(base)
        if len(set(active_keys)) != len(active_keys):
            raise ValueError("Duplicate native schedule references")
        all_keys = active_keys + [key for key in base if key not in active_keys]
        for position, legacy_key in enumerate(all_keys):
            stop = copy.deepcopy(base.get(legacy_key, {}))
            user_selected = legacy_key.startswith("place|")
            selected_legacy = legacy_key[6:] if user_selected else str(stop.get("place_id") or "")
            if selected_legacy and selected_legacy not in place_map:
                raise ValueError("Schedule references an unknown place")
            if legacy_key not in base and not user_selected:
                raise ValueError("Unknown native schedule reference")
            decision_id = stable(f"decision:{day_key}:{legacy_key}")
            category = next((p.category for p in places if p.legacy_id == selected_legacy), "other")
            canonical = "coffee" if category.casefold() in {"coffee", "cafe", "καφές"} else canonical_category(category)
            pool = [p for p in places if p.legacy_id == selected_legacy or
                    (canonical != "other" and ("coffee" if p.category.casefold() in {"coffee", "cafe", "καφές"}
                                              else canonical_category(p.category)) == canonical)]
            candidates = [Candidate(id=stable(f"candidate:{decision_id}:{p.id}"), user_place_id=p.id) for p in pool]
            selected = next((c.id for c in candidates if c.user_place_id == place_map.get(selected_legacy)), None)
            edits = state.get("scheduleEditsByItemID", {}).get(legacy_key, {})
            time_value = edits.get("time") if edits.get("time") is not None else stop.get("time")
            if user_selected:
                warnings.append("Native place references acquired a stable slot during migration; old swap intent was not recoverable.")
            decisions.append(Decision(id=decision_id, legacy_key=legacy_key, day_id=day_id, position=position,
                                      purpose=str(stop.get("purpose") or stop.get("activity") or category),
                                      time=str(time_value) if time_value is not None else None,
                                      duration_minutes=stop.get("duration_minutes"), period=stop.get("period"),
                                      is_scheduled=legacy_key in active_keys,
                                      time_locked=edits.get("time") is not None, order_locked=saved_order is not None,
                                      option_set_id=stable(f"option-set:{decision_id}:1"), candidates=candidates,
                                      selected_candidate_id=selected,
                                      suggested_candidate_id=selected if not user_selected else None,
                                      selection_owner="user" if user_selected else "ai",
                                      selection_locked=user_selected and selected is not None,
                                      context={"legacy_stop": stop, "category": category}))
    date_context = brief.get("date_range") or research.get("trip_context", {}).get("date_range") or {}
    arrival = optional_date(brief.get("startDate") or date_context.get("arrival"))
    departure = optional_date(brief.get("endDate") or date_context.get("departure"))
    unknown = brief.get("dateIsUnknown") or date_context.get("dates_unknown")
    mode = "unknown" if unknown else ("fixed" if arrival and departure else "flexible")
    modules = {key: copy.deepcopy(value) for key, value in research.items() if key not in {"places", "sources", "itinerary", "schema_version"}}
    modules["itinerary"] = {key: copy.deepcopy(value) for key, value in (research.get("itinerary") or {}).items() if key != "days"}
    if native:
        modules["native_extensions"] = {key: copy.deepcopy(value) for key, value in payload.items()
                                        if key not in set(APP_STATE_KEYS) | {"id", "brief", "research"}}
    return NormalizedTrip(id=trip_id, owner_id=owner_id, legacy_trip_key=trip_key,
                          destination=str(brief.get("destination") or research.get("trip_context", {}).get("destination") or ""),
                          date_mode=mode, arrival_date=arrival, departure_date=departure, brief=brief,
                          places=places, sources=sources, claims=claims, days=days, decisions=decisions,
                          app_owned_state=state, legacy_modules=modules, id_map=id_map,
                          warnings=list(dict.fromkeys(warnings)), source_hash=document_hash(original))


def export_research_v1(trip):
    """Selected plan projection, not a replacement for the full v2/lock overlay."""
    if trip.catalog_entity_ids:
        raise ValueError("Catalog projections require retrieved canonical facts; use the backend catalog projection path")
    result = copy.deepcopy(trip.legacy_modules)
    result.pop("native_extensions", None)
    result["schema_version"] = "trippy-research-v1"
    context = result.get("trip_context") or {}
    context.update(copy.deepcopy(trip.brief))
    context["destination"] = trip.destination
    context["date_range"] = {**context.get("date_range", {}),
                             "arrival": trip.arrival_date.isoformat() if trip.arrival_date else None,
                             "departure": trip.departure_date.isoformat() if trip.departure_date else None,
                             "dates_unknown": trip.date_mode == "unknown"}
    result["trip_context"] = context
    result["places"] = []
    legacy_places = {place.id: place.legacy_id for place in trip.places}
    for place in trip.places:
        row = copy.deepcopy(place.legacy_fields)
        row.update(id=place.legacy_id, name=place.name, category=place.category, address=place.address,
                   official_url=place.official_url, description=place.description, tags=place.tags,
                   coordinates={**place.coordinate_extensions, **place.coordinates.model_dump()})
        # Old clients do not understand verification state. Hide imported numeric
        # ratings in the projection, preserving the claim in the normalized data.
        if row.get("rating"):
            platform = row["rating"].get("platform") if isinstance(row["rating"], dict) else None
            row["rating"] = {"value": None, "platform": platform, "review_count": None,
                             "verification_status": "unverified"}
        result["places"].append(row)
    result["sources"] = [copy.deepcopy(source.legacy_fields) for source in trip.sources]
    candidate_place = {candidate.id: candidate.user_place_id for decision in trip.decisions for candidate in decision.candidates}
    exported_days = []
    for day in trip.days:
        row = copy.deepcopy(day.legacy_fields)
        row["day"] = day.day_number
        if day.local_date:
            row["date"] = day.local_date.isoformat()
        row["stops"] = []
        for decision in sorted((d for d in trip.decisions if d.day_id == day.id and d.is_scheduled), key=lambda d: d.position):
            stop = copy.deepcopy(decision.context.get("legacy_stop", {}))
            stop.update(slot_id=str(decision.id), activity=decision.purpose, time=decision.time,
                        place_id=legacy_places.get(candidate_place.get(decision.selected_candidate_id)),
                        duration_minutes=decision.duration_minutes, period=decision.period, status="proposed")
            row["stops"].append(stop)
        exported_days.append(row)
    result["itinerary"] = {**result.get("itinerary", {}), "days": exported_days}
    return result
