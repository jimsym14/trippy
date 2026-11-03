"""Transactional local import of the legacy overlay into relational records.

Does not publish catalog records or mutate a prior trip. A changed import is a
reviewable conflict until Stage 2 supplies revision-aware patch transactions.
"""

import copy
from datetime import time
from decimal import Decimal, InvalidOperation
from uuid import uuid5

from sqlalchemy import insert, select

from trippy.contracts import NormalizedTrip
from . import schema_v1 as s


class ImportConflict(ValueError):
    pass


def import_trip(connection, trip, *, backup_ref=None):
    with connection.begin_nested():
        return _import_trip(connection, trip, backup_ref=backup_ref)


def _import_trip(connection, trip, *, backup_ref=None):
    if connection.dialect.name != "sqlite":
        raise ValueError("Legacy persistence is local-only until provider permissions and connected ownership are verified")
    if trip.catalog_entity_ids:
        raise ValueError("Legacy imports remain private; canonical references require the catalog retrieval path")
    owner_id, trip_id = str(trip.owner_id), str(trip.id)

    def stable(key):
        return str(uuid5(trip.id, key))

    def put(table, **row):
        connection.execute(insert(table), row)

    if connection.execute(select(s.trips.c.id).where(s.trips.c.id == trip_id)).first():
        existing = connection.execute(select(s.legacy_migration_state.c.source_hash).where(
            s.legacy_migration_state.c.trip_id == trip_id, s.legacy_migration_state.c.owner_id == owner_id)).scalar_one_or_none()
        if existing == trip.source_hash:
            return {"status": "already_imported", "trip_id": trip_id}
        raise ImportConflict("Trip already exists; preview and apply a revision-aware patch instead of overwriting user state")
    if not connection.execute(select(s.app_users.c.id).where(s.app_users.c.id == owner_id)).first():
        put(s.app_users, id=owner_id)
    put(s.trips, id=trip_id, owner_id=owner_id, destination=trip.destination,
        date_mode=trip.date_mode, arrival_date=trip.arrival_date, departure_date=trip.departure_date)
    policy_id = stable("policy:legacy-local")
    provider = "legacy-local:" + trip_id
    put(s.source_policies, id=policy_id, provider=provider, policy_version="1", status="pending",
        allowed_fields=[], can_retain_raw=False, can_use_in_prompt=False)
    run_id = stable("run:" + trip.source_hash)
    put(s.research_runs, id=run_id, owner_id=owner_id, trip_id=trip_id,
        source_schema="trippy-research-v1", content_hash=trip.source_hash)

    def extension(key, value):
        put(s.research_extensions, id=stable("extension:" + key), owner_id=owner_id,
            research_run_id=run_id, record_key=key, value=value, policy_id=policy_id)

    for key, value in trip.brief.items():
        put(s.trip_preferences, id=stable("preference:" + key), owner_id=owner_id,
            trip_id=trip_id, preference_key=key, value=value,
            strength="unknown" if value is None else "prefer")
    for place in trip.places:
        put(s.user_places, id=str(place.id), owner_id=owner_id, origin_trip_id=trip_id,
            legacy_key=place.legacy_id, name=place.name, category=place.category,
            description=place.description, address=place.address, official_url=place.official_url,
            latitude=place.coordinates.latitude, longitude=place.coordinates.longitude,
            identity_status=place.identity_status)
        for tag in dict.fromkeys(place.tags):
            put(s.user_place_tags, user_place_id=str(place.id), owner_id=owner_id, tag=tag)
        extension("place:" + str(place.id), {"legacy_fields": place.legacy_fields,
                  "coordinate_status": place.coordinates.status, "coordinate_extensions": place.coordinate_extensions})
    for source in trip.sources:
        put(s.source_records, id=str(source.id), owner_id=owner_id, scope_key=owner_id, policy_id=policy_id,
            url=source.url, publisher=source.publisher, checked_on=source.checked_on)
        extension("source:" + str(source.id), {"legacy_id": source.legacy_id, "legacy_fields": source.legacy_fields})
    for claim in trip.claims:
        # Record-level citations are not field-level verification. Keep all
        # source links as unverified extensions; never select one arbitrarily.
        extension("claim:" + str(claim.id), claim.model_dump(mode="json"))
        if len(claim.source_ids) != 1:
            continue
        put(s.observations, id=str(claim.id), owner_id=owner_id, scope_key=owner_id,
            user_place_id=str(claim.user_place_id), source_id=str(claim.source_ids[0]), research_run_id=run_id,
            field_key=claim.field_key, value=claim.value, checked_on=claim.checked_on,
            verification_status=claim.verification_status)
        if claim.field_key == "rating" and isinstance(claim.value, dict):
            rating = claim.value
            if rating.get("scale") == 5 and rating.get("platform") and valid_decimal(rating.get("value"), maximum=5) is not None:
                count = rating.get("review_count")
                if count is not None and (isinstance(count, bool) or not isinstance(count, int) or count < 0):
                    count = None
                put(s.rating_snapshots, id=stable("rating:" + str(claim.id)), owner_id=owner_id, scope_key=owner_id,
                    observation_id=str(claim.id), rating_value=valid_decimal(rating["value"], maximum=5),
                    rating_scale=5, platform=rating["platform"], review_count=count)
    for day in trip.days:
        put(s.trip_days, id=str(day.id), owner_id=owner_id, trip_id=trip_id, local_date=day.local_date,
            day_number=day.day_number, theme=day.theme, order_locked=day.order_locked)
        extension("day:" + str(day.id), {"legacy_key": day.legacy_key, "legacy_fields": day.legacy_fields})
    for decision in trip.decisions:
        decision_id = str(decision.id)
        put(s.trip_decisions, id=decision_id, owner_id=owner_id, trip_id=trip_id,
            kind=decision.kind, purpose=decision.purpose, legacy_key=decision.legacy_key,
            context=decision.context, revision=decision.revision)
        if decision.kind == "activity" and decision.day_id:
            try:
                clock = time.fromisoformat(decision.time) if decision.time else None
            except ValueError:
                clock = None
            put(s.activity_slots, decision_id=decision_id, owner_id=owner_id, trip_id=trip_id,
                day_id=str(decision.day_id), position=decision.position, starts_at=clock,
                duration_minutes=decision.duration_minutes, period=decision.period,
                is_scheduled=decision.is_scheduled, time_locked=decision.time_locked, order_locked=decision.order_locked)
            # Human times such as "after lunch" are not discarded or parsed as
            # precise timestamps. The compatibility projection reads this value.
            extension("decision-time:" + decision_id, {"time": decision.time})
        put(s.decision_option_sets, id=str(decision.option_set_id), owner_id=owner_id, decision_id=decision_id,
            version=1, retrieval_context=decision.context, completeness="partial")
        for candidate in decision.candidates:
            put(s.decision_candidates, id=str(candidate.id), owner_id=owner_id, decision_id=decision_id,
                option_set_id=str(decision.option_set_id), user_place_id=str(candidate.user_place_id),
                eligibility_status=candidate.eligibility_status)
        put(s.decision_selections, decision_id=decision_id, owner_id=owner_id,
            selected_candidate_id=str(decision.selected_candidate_id) if decision.selected_candidate_id else None,
            suggested_candidate_id=str(decision.suggested_candidate_id) if decision.suggested_candidate_id else None,
            selection_owner=decision.selection_owner, selection_locked=decision.selection_locked, revision=decision.revision)
        put(s.selection_history, id=stable("history:" + decision_id), owner_id=owner_id, decision_id=decision_id,
            candidate_id=str(decision.selected_candidate_id) if decision.selected_candidate_id else None,
            revision=decision.revision, actor=decision.selection_owner, selection_locked=decision.selection_locked)
    state = trip.app_owned_state
    for key, reaction in (state.get("reactionsByItemID") or {}).items():
        put(s.user_reactions, id=stable("reaction:" + key), owner_id=owner_id, trip_id=trip_id,
            legacy_item_key=key, reaction=reaction)
    for key, edits in (state.get("scheduleEditsByItemID") or {}).items():
        for field, value in edits.items():
            put(s.user_overrides, id=stable(f"override:{key}:{field}"), owner_id=owner_id, trip_id=trip_id,
                legacy_item_key=key, field_key=field, value=value)
    for index, entry in enumerate(state.get("budgetEntries") or []):
        put(s.cost_lines, id=stable("budget:" + str(entry.get("id") or index)), owner_id=owner_id, trip_id=trip_id,
            title=entry.get("title") or "User expense", amount=valid_decimal(entry.get("amount")),
            currency=entry.get("currency"), basis=entry.get("basis") or "group", origin="user")
    put(s.legacy_migration_state, trip_id=trip_id, owner_id=owner_id, source_hash=trip.source_hash,
        adapter_version=trip.adapter_version, id_map=trip.id_map,
        app_owned_extensions=state, backup_ref=backup_ref)
    extension("modules", trip.legacy_modules)
    extension("import-info", {"legacy_trip_key": trip.legacy_trip_key, "warnings": trip.warnings})
    return {"status": "imported", "trip_id": trip_id}


def valid_decimal(value, maximum=None):
    if value is None or isinstance(value, bool):
        return None
    try:
        result = Decimal(str(value))
        if not result.is_finite() or result < 0 or (maximum is not None and result > maximum):
            return None
        return result
    except InvalidOperation:
        return None


def load_trip(connection, *, trip_id, owner_id):
    """Owner is mandatory even in local mode; return no other owner's data."""
    trip_id, owner_id = str(trip_id), str(owner_id)
    row = connection.execute(select(s.trips).where(s.trips.c.id == trip_id, s.trips.c.owner_id == owner_id)).mappings().first()
    if row is None:
        return None

    def rows(table):
        statement = select(table).where(table.c.owner_id == owner_id)
        if "trip_id" in table.c:
            statement = statement.where(table.c.trip_id == trip_id)
        return list(connection.execute(statement).mappings())

    migration = connection.execute(select(s.legacy_migration_state).where(
        s.legacy_migration_state.c.trip_id == trip_id, s.legacy_migration_state.c.owner_id == owner_id)).mappings().one()
    run = connection.execute(select(s.research_runs).where(
        s.research_runs.c.trip_id == trip_id, s.research_runs.c.owner_id == owner_id)).mappings().one()
    extensions = {r["record_key"]: r["value"] for r in rows(s.research_extensions) if r["research_run_id"] == run["id"]}
    places = []
    place_rows = [r for r in rows(s.user_places) if r["origin_trip_id"] == trip_id]
    tags = rows(s.user_place_tags)
    for place in place_rows:
        extras = extensions.get("place:" + place["id"], {})
        places.append(dict(id=place["id"], legacy_id=place["legacy_key"], name=place["name"], category=place["category"],
                           address=place["address"], official_url=place["official_url"], description=place["description"],
                           identity_status=place["identity_status"],
                           coordinates={"latitude": place["latitude"], "longitude": place["longitude"], "status": extras.get("coordinate_status", "unknown")},
                           coordinate_extensions=extras.get("coordinate_extensions", {}),
                           tags=[r["tag"] for r in tags if r["user_place_id"] == place["id"]], legacy_fields=extras.get("legacy_fields", {})))
    sources = [dict(id=r["id"], legacy_id=extensions["source:" + r["id"]]["legacy_id"], url=r["url"], publisher=r["publisher"],
                    checked_on=r["checked_on"], legacy_fields=extensions["source:" + r["id"]]["legacy_fields"])
               for r in rows(s.source_records) if "source:" + r["id"] in extensions]
    days = []
    for day in [r for r in rows(s.trip_days) if r["trip_id"] == trip_id]:
        extras = extensions["day:" + day["id"]]
        days.append(dict(id=day["id"], legacy_key=extras["legacy_key"], day_number=day["day_number"], local_date=day["local_date"],
                         theme=day["theme"], order_locked=day["order_locked"], legacy_fields=extras["legacy_fields"]))
    slots = {r["decision_id"]: r for r in rows(s.activity_slots)}
    selections = {r["decision_id"]: r for r in rows(s.decision_selections)}
    option_sets = rows(s.decision_option_sets)
    candidates = rows(s.decision_candidates)
    decisions = []
    for decision in [r for r in rows(s.trip_decisions) if r["trip_id"] == trip_id]:
        slot = slots.get(decision["id"], {})
        selected = selections[decision["id"]]
        option_set = next(r for r in option_sets if r["decision_id"] == decision["id"])
        decisions.append(dict(id=decision["id"], legacy_key=decision["legacy_key"], kind=decision["kind"], purpose=decision["purpose"],
                              day_id=slot.get("day_id"), position=slot.get("position", 0), is_scheduled=slot.get("is_scheduled", False),
                              time=extensions.get("decision-time:" + decision["id"], {}).get("time"),
                              duration_minutes=slot.get("duration_minutes"), period=slot.get("period"),
                              time_locked=slot.get("time_locked", False), order_locked=slot.get("order_locked", False),
                              option_set_id=option_set["id"], candidates=[dict(id=c["id"], user_place_id=c["user_place_id"],
                              eligibility_status=c["eligibility_status"]) for c in candidates if c["option_set_id"] == option_set["id"]],
                              selected_candidate_id=selected["selected_candidate_id"], suggested_candidate_id=selected["suggested_candidate_id"],
                              selection_owner=selected["selection_owner"], selection_locked=selected["selection_locked"],
                              revision=selected["revision"], context=decision["context"]))
    info = extensions["import-info"]
    brief = {r["preference_key"]: r["value"] for r in rows(s.trip_preferences) if r["trip_id"] == trip_id}
    return NormalizedTrip(id=trip_id, owner_id=owner_id, legacy_trip_key=info["legacy_trip_key"], destination=row["destination"],
                          date_mode=row["date_mode"], arrival_date=row["arrival_date"], departure_date=row["departure_date"],
                          brief=brief, places=places, sources=sources, days=sorted(days, key=lambda d: d["day_number"]),
                          decisions=decisions, claims=[value for key, value in extensions.items() if key.startswith("claim:")],
                          app_owned_state=copy.deepcopy(migration["app_owned_extensions"]), legacy_modules=extensions["modules"],
                          id_map=migration["id_map"], warnings=info["warnings"], source_hash=migration["source_hash"])
