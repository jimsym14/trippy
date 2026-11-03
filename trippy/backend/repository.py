"""Ownership checks, optimistic revisions and durable mutation receipts."""

from uuid import uuid4
from sqlalchemy import insert, select, update
from fastapi.encoders import jsonable_encoder

from trippy.data import schema_v2 as s
from .common import DomainError, fingerprint, row, transaction


def ensure_user(connection, owner):
    if connection.dialect.name == "postgresql":
        from sqlalchemy.dialects.postgresql import insert as upsert
    else:
        from sqlalchemy.dialects.sqlite import insert as upsert
    connection.execute(upsert(s.app_users).values(id=owner).on_conflict_do_nothing(index_elements=["id"]))


def receipt(connection, owner, key, request):
    ensure_user(connection, owner)
    # Serializes same-owner API commands, including first insert of a key.
    row(connection, s.app_users, s.app_users.c.id == owner, lock=True)
    value = connection.execute(select(s.mutation_receipts).where(
        s.mutation_receipts.c.owner_id == owner, s.mutation_receipts.c.request_key == key)).mappings().first()
    if value:
        if value["fingerprint"] != fingerprint(request):
            raise DomainError("idempotency_key_reused")
        return value["response"]
    return None


def save_receipt(connection, owner, key, request, response):
    encoded = jsonable_encoder(response)
    connection.execute(insert(s.mutation_receipts).values(owner_id=owner, request_key=key,
                       fingerprint=fingerprint(request), response=encoded))
    return encoded


class Repository:
    def __init__(self, engine):
        self.engine = engine

    def list_trips(self, owner, *, after=None, limit=30):
        with self.engine.connect() as c:
            query = select(s.trips).where(s.trips.c.owner_id == owner)
            if after:
                query = query.where(s.trips.c.id > after)
            return [dict(r) for r in c.execute(query.order_by(s.trips.c.id).limit(limit)).mappings()]

    def get_trip(self, owner, trip_id):
        with self.engine.connect() as c:
            trip = row(c, s.trips, (s.trips.c.id == trip_id) & (s.trips.c.owner_id == owner))
            decisions = c.execute(select(s.trip_decisions).where(s.trip_decisions.c.owner_id == owner,
                                  s.trip_decisions.c.trip_id == trip_id).order_by(s.trip_decisions.c.id)).mappings()
            trip["decisions"] = [self.decision(c, owner, d["id"], trip_id) for d in decisions]
            trip["days"] = [dict(r) for r in c.execute(select(s.trip_days).where(
                s.trip_days.c.trip_id == trip_id, s.trip_days.c.owner_id == owner)
                .order_by(s.trip_days.c.day_number)).mappings()]
            return trip

    def create_trip(self, owner, key, request):
        shape = {"operation": "create_trip", **request}
        with transaction(self.engine) as c:
            cached = receipt(c, owner, key, shape)
            if cached is not None:
                return cached
            trip_id = str(uuid4())
            c.execute(insert(s.trips).values(id=trip_id, owner_id=owner, destination=request["destination"].strip()))
            return save_receipt(c, owner, key, shape, row(c, s.trips, s.trips.c.id == trip_id))

    def decision(self, c, owner, decision_id, trip_id, *, lock=False):
        decision = row(c, s.trip_decisions, (s.trip_decisions.c.id == decision_id) &
                       (s.trip_decisions.c.owner_id == owner) & (s.trip_decisions.c.trip_id == trip_id), lock=lock)
        decision["selection"] = row(c, s.decision_selections,
                                   (s.decision_selections.c.decision_id == decision_id) &
                                   (s.decision_selections.c.owner_id == owner), lock=lock)
        decision["candidates"] = [dict(r) for r in c.execute(select(s.decision_candidates).where(
            s.decision_candidates.c.decision_id == decision_id, s.decision_candidates.c.owner_id == owner)
            .order_by(s.decision_candidates.c.id)).mappings()]
        slot = c.execute(select(s.activity_slots).where(s.activity_slots.c.decision_id == decision_id,
                         s.activity_slots.c.owner_id == owner, s.activity_slots.c.trip_id == trip_id)).mappings().first()
        decision["slot"] = dict(slot) if slot is not None else None
        return decision

    def mutate_selection(self, owner, trip_id, decision_id, key, request):
        shape = {"operation": "selection", "trip_id": trip_id, "decision_id": decision_id, **request}
        with transaction(self.engine) as c:
            cached = receipt(c, owner, key, shape)
            if cached is not None:
                return cached
            trip = row(c, s.trips, (s.trips.c.id == trip_id) & (s.trips.c.owner_id == owner), lock=True)
            decision = self.decision(c, owner, decision_id, trip_id, lock=True)
            selection = decision["selection"]
            if trip["revision"] != request["expected_trip_revision"] or decision["revision"] != request["expected_revision"]:
                raise DomainError("revision_conflict")
            candidate = selection["selected_candidate_id"]
            locked = selection["selection_locked"]
            action = request["action"]
            if action == "select":
                candidate = request["candidate_id"]
            elif action == "lock":
                if candidate is None:
                    raise DomainError("selection_required")
                locked = True
            elif action == "unlock":
                locked = False
            else:
                history = row(c, s.selection_history,
                              (s.selection_history.c.decision_id == decision_id) &
                              (s.selection_history.c.owner_id == owner) &
                              (s.selection_history.c.revision == request["history_revision"]))
                candidate, locked = history["candidate_id"], history["selection_locked"]
            selected = next((v for v in decision["candidates"] if v["id"] == candidate), None)
            if candidate is not None and selected is None:
                raise DomainError("candidate_not_in_decision", 422)
            conflict = "candidate_unavailable" if selected and selected["eligibility_status"] in {"ineligible", "conflict"} else None
            revision = decision["revision"] + 1
            # Ensure an undo baseline also exists for newly created decisions.
            baseline = c.execute(select(s.selection_history.c.id).where(s.selection_history.c.decision_id == decision_id,
                                 s.selection_history.c.revision == decision["revision"])).first()
            if baseline is None:
                c.execute(insert(s.selection_history).values(owner_id=owner, decision_id=decision_id,
                          candidate_id=selection["selected_candidate_id"], revision=decision["revision"],
                          actor=selection["selection_owner"], selection_locked=selection["selection_locked"]))
            c.execute(update(s.decision_selections).where(s.decision_selections.c.decision_id == decision_id).values(
                selected_candidate_id=candidate, selection_locked=locked, selection_owner="user",
                conflict_reason=conflict, revision=revision))
            c.execute(update(s.trip_decisions).where(s.trip_decisions.c.id == decision_id).values(revision=revision))
            c.execute(update(s.trips).where(s.trips.c.id == trip_id).values(revision=trip["revision"] + 1))
            c.execute(insert(s.selection_history).values(owner_id=owner, decision_id=decision_id,
                      candidate_id=candidate, revision=revision, actor="user", selection_locked=locked))
            return save_receipt(c, owner, key, shape, {"trip_revision": trip["revision"] + 1,
                                "decision": self.decision(c, owner, decision_id, trip_id)})

    def patch_trip(self, owner, trip_id, key, request):
        shape = {"operation": "patch_trip", "trip_id": trip_id, **request}
        with transaction(self.engine) as c:
            cached = receipt(c, owner, key, shape)
            if cached is not None:
                return cached
            trip = row(c, s.trips, (s.trips.c.id == trip_id) & (s.trips.c.owner_id == owner), lock=True)
            if trip["revision"] != request["expected_revision"]:
                raise DomainError("revision_conflict")
            changes = {k: v for k, v in request.items() if k != "expected_revision"}
            # Parse dates at the service boundary; request fingerprint stays JSON.
            from datetime import date
            for key_date in ("arrival_date", "departure_date"):
                if changes.get(key_date) is not None:
                    changes[key_date] = date.fromisoformat(changes[key_date])
            merged = {**trip, **changes}
            if merged["date_mode"] is None or (merged["date_mode"] == "fixed" and
                (merged["arrival_date"] is None or merged["departure_date"] is None)):
                raise DomainError("invalid_trip_dates", 422)
            if merged["arrival_date"] and merged["departure_date"] and merged["departure_date"] < merged["arrival_date"]:
                raise DomainError("invalid_trip_dates", 422)
            c.execute(update(s.trips).where(s.trips.c.id == trip_id).values(**changes, revision=trip["revision"] + 1))
            return save_receipt(c, owner, key, shape, {"trip": row(c, s.trips, s.trips.c.id == trip_id),
                                "checks_status": "needs_revalidation"})

    def _bump_slot_revision(self, c, owner, trip_id, decision_id):
        decision = self.decision(c, owner, decision_id, trip_id, lock=True)
        revision = decision["revision"] + 1
        selection = decision["selection"]
        baseline = c.execute(select(s.selection_history.c.id).where(s.selection_history.c.decision_id == decision_id,
                             s.selection_history.c.revision == decision["revision"])).first()
        if baseline is None:
            c.execute(insert(s.selection_history).values(owner_id=owner, decision_id=decision_id,
                      candidate_id=selection["selected_candidate_id"], revision=decision["revision"],
                      actor=selection["selection_owner"], selection_locked=selection["selection_locked"]))
        c.execute(update(s.trip_decisions).where(s.trip_decisions.c.id == decision_id).values(revision=revision))
        c.execute(update(s.decision_selections).where(s.decision_selections.c.decision_id == decision_id).values(revision=revision))
        c.execute(insert(s.selection_history).values(owner_id=owner, decision_id=decision_id,
                  candidate_id=selection["selected_candidate_id"], revision=revision,
                  actor=selection["selection_owner"], selection_locked=selection["selection_locked"]))

    def mutate_slot(self, owner, trip_id, decision_id, key, request):
        shape = {"operation": "slot", "trip_id": trip_id, "decision_id": decision_id, **request}
        with transaction(self.engine) as c:
            cached = receipt(c, owner, key, shape)
            if cached is not None:
                return cached
            trip = row(c, s.trips, (s.trips.c.id == trip_id) & (s.trips.c.owner_id == owner), lock=True)
            decision = self.decision(c, owner, decision_id, trip_id, lock=True)
            if trip["revision"] != request["expected_trip_revision"] or decision["revision"] != request["expected_revision"]:
                raise DomainError("revision_conflict")
            slot = row(c, s.activity_slots, (s.activity_slots.c.decision_id == decision_id) &
                       (s.activity_slots.c.trip_id == trip_id) & (s.activity_slots.c.owner_id == owner), lock=True)
            changes = {k: v for k, v in request.items() if k not in {"expected_revision", "expected_trip_revision"}}
            if changes.get("starts_at") is not None:
                from datetime import time
                changes["starts_at"] = time.fromisoformat(changes["starts_at"])
            c.execute(update(s.activity_slots).where(s.activity_slots.c.decision_id == decision_id).values(**changes))
            self._bump_slot_revision(c, owner, trip_id, decision_id)
            c.execute(update(s.trips).where(s.trips.c.id == trip_id).values(revision=trip["revision"] + 1))
            return save_receipt(c, owner, key, shape, {"trip_revision": trip["revision"] + 1,
                "slot": row(c, s.activity_slots, s.activity_slots.c.decision_id == slot["decision_id"]),
                "checks_status": "needs_revalidation"})

    def reorder_day(self, owner, trip_id, day_id, key, request):
        shape = {"operation": "day_order", "trip_id": trip_id, "day_id": day_id, **request}
        with transaction(self.engine) as c:
            cached = receipt(c, owner, key, shape)
            if cached is not None:
                return cached
            trip = row(c, s.trips, (s.trips.c.id == trip_id) & (s.trips.c.owner_id == owner), lock=True)
            row(c, s.trip_days, (s.trip_days.c.id == day_id) & (s.trip_days.c.trip_id == trip_id) &
                (s.trip_days.c.owner_id == owner), lock=True)
            if trip["revision"] != request["expected_trip_revision"]:
                raise DomainError("revision_conflict")
            slots = c.execute(select(s.activity_slots).where(s.activity_slots.c.day_id == day_id,
                s.activity_slots.c.trip_id == trip_id, s.activity_slots.c.owner_id == owner)
                .order_by(s.activity_slots.c.decision_id).with_for_update()).mappings().all()
            if {v["decision_id"] for v in slots} != set(request["decision_ids"]):
                raise DomainError("day_order_must_preserve_all_slots", 422)
            for position, decision_id in enumerate(request["decision_ids"]):
                c.execute(update(s.activity_slots).where(s.activity_slots.c.decision_id == decision_id).values(position=position))
                self._bump_slot_revision(c, owner, trip_id, decision_id)
            c.execute(update(s.trips).where(s.trips.c.id == trip_id).values(revision=trip["revision"] + 1))
            return save_receipt(c, owner, key, shape, {"trip_revision": trip["revision"] + 1,
                                "decision_ids": request["decision_ids"], "checks_status": "needs_revalidation"})

    def apply_proposals(self, c, job, result):
        """Called only inside a transaction holding the current job lease/fence."""
        if not result.proposals:
            return []
        if job["task_type"] != "trip_research" or job["trip_id"] is None:
            raise DomainError("proposal_scope_invalid", 422)
        owner, trip_id = job["owner_id"], job["trip_id"]
        trip = row(c, s.trips, (s.trips.c.id == trip_id) & (s.trips.c.owner_id == owner), lock=True)
        snapshot = job["payload"]["snapshot"]
        allowed = {d["id"]: d for d in snapshot["decisions"]}
        applied = []
        for proposal in result.proposals:
            did, cid = str(proposal.decision_id), str(proposal.candidate_id)
            original = allowed.get(did)
            if original is None or cid not in {v["id"] for v in original["candidates"]} or proposal.expected_revision != original["revision"]:
                raise DomainError("proposal_outside_snapshot", 422)
            decision = self.decision(c, owner, did, trip_id, lock=True)
            selection = decision["selection"]
            if trip["revision"] != snapshot["revision"] or decision["revision"] != proposal.expected_revision:
                applied.append({"decision_id": did, "status": "stale_skipped"})
                continue
            selected = next((v for v in decision["candidates"] if v["id"] == cid), None)
            if selected is None:
                raise DomainError("proposal_candidate_missing", 422)
            # User selections remain user-owned even after unlocking. A new AI
            # suggestion can be offered without silently replacing that choice.
            values = {"suggested_candidate_id": cid}
            if selection["selection_owner"] == "ai" and not selection["selection_locked"] and selected["eligibility_status"] not in {"ineligible", "conflict"}:
                values["selected_candidate_id"] = cid
            revision = decision["revision"] + 1
            values["revision"] = revision
            c.execute(update(s.decision_selections).where(s.decision_selections.c.decision_id == did).values(**values))
            c.execute(update(s.trip_decisions).where(s.trip_decisions.c.id == did).values(revision=revision))
            c.execute(insert(s.selection_history).values(owner_id=owner, decision_id=did,
                      candidate_id=values.get("selected_candidate_id", selection["selected_candidate_id"]),
                      revision=revision, actor=selection["selection_owner"], selection_locked=selection["selection_locked"]))
            applied.append({"decision_id": did, "status": "suggested"})
        if any(a["status"] == "suggested" for a in applied):
            c.execute(update(s.trips).where(s.trips.c.id == trip_id).values(revision=trip["revision"] + 1))
        return applied
