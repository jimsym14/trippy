"""Database queue with leases, fencing, reconnectable event cursors and retries."""

from dataclasses import dataclass
from datetime import timedelta, timezone
from decimal import Decimal
from uuid import uuid4
from sqlalchemy import and_, func, insert, or_, select, text, update

from trippy.data import schema_v2 as s
from .common import DomainError, fingerprint, row, transaction, utcnow
from .repository import Repository, receipt, save_receipt


@dataclass(frozen=True)
class Lease:
    job_id: str
    token: str
    fence: int


def require_lease(job, lease, now):
    deadline = job["lease_until"]
    if deadline is not None and deadline.tzinfo is None:
        deadline = deadline.replace(tzinfo=timezone.utc)
    if job["status"] != "running" or job["lease_token"] != lease.token or job["fence"] != lease.fence or deadline is None or deadline <= now:
        raise DomainError("lease_lost")


def emit(c, job, kind, payload):
    # All callers hold the parent job row lock, making sequences atomic.
    sequence = c.execute(select(func.coalesce(func.max(s.job_events.c.sequence), 0)).where(
                         s.job_events.c.job_id == job["id"])).scalar_one() + 1
    c.execute(insert(s.job_events).values(owner_id=job["owner_id"], job_id=job["id"],
              sequence=sequence, kind=kind, payload=payload))


class Queue:
    def __init__(self, engine, *, provider="fake", job_cap=Decimal("0"), max_attempts=3, lease_seconds=60, max_concurrency=1):
        if max_attempts < 1 or max_attempts > 10 or lease_seconds < 1 or lease_seconds > 3600:
            raise ValueError("Bounded queue limits are required")
        if not isinstance(job_cap, Decimal) or not job_cap.is_finite() or job_cap < 0:
            raise ValueError("Finite nonnegative job cap required")
        if type(max_concurrency) is not int or not 1 <= max_concurrency <= 20:
            raise ValueError("Provider concurrency must be between 1 and 20")
        self.engine, self.provider, self.job_cap = engine, provider, job_cap
        self.max_attempts, self.lease_seconds = max_attempts, lease_seconds
        self.max_concurrency = max_concurrency
        self.repository = Repository(engine)

    def enqueue(self, principal, key, request):
        owner = principal.owner_id
        shape = {"operation": "enqueue", **request}
        if request["task_type"] == "catalog_enrichment" and not principal.admin:
            raise DomainError("admin_required", 403)
        if Decimal(request["budget_amount"]) > self.job_cap:
            raise DomainError("job_budget_above_server_cap", 422)
        with transaction(self.engine) as c:
            cached = receipt(c, owner, key, shape)
            if cached is not None:
                return cached
            snapshot = None
            if request.get("trip_id"):
                trip = row(c, s.trips, (s.trips.c.id == request["trip_id"]) & (s.trips.c.owner_id == owner), lock=True)
                if trip["revision"] != request["expected_trip_revision"]:
                    raise DomainError("revision_conflict")
                snapshot = {"revision": trip["revision"], "geography_id": trip["geography_id"], "decisions": []}
                decisions = c.execute(select(s.trip_decisions.c.id).where(s.trip_decisions.c.trip_id == trip["id"],
                    s.trip_decisions.c.owner_id == owner).order_by(s.trip_decisions.c.id).limit(101)).scalars().all()
                if len(decisions) > 100:
                    raise DomainError("trip_research_scope_too_large", 422)
                for did in decisions:
                    decision = self.repository.decision(c, owner, did, trip["id"])
                    if len(decision["candidates"]) > 100:
                        raise DomainError("candidate_scope_too_large", 422)
                    snapshot["decisions"].append({"id": did, "revision": decision["revision"],
                        "candidates": [{"id": v["id"]} for v in decision["candidates"]]})
            elif request.get("city_id"):
                city = row(c, s.geographies, s.geographies.c.id == request["city_id"])
                if city["kind"] != "city":
                    raise DomainError("city_required", 422)
            dedupe = fingerprint(shape)
            existing = c.execute(select(s.research_jobs).where(s.research_jobs.c.owner_id == owner,
                s.research_jobs.c.dedupe_key == dedupe, s.research_jobs.c.status.in_(["queued", "running"]))
                ).mappings().first()
            if existing:
                return save_receipt(c, owner, key, shape, {"job_id": existing["id"], "status": existing["status"], "deduplicated": True})
            job_id, now = str(uuid4()), utcnow()
            payload = {**request, "provider": self.provider, "snapshot": snapshot}
            c.execute(insert(s.research_jobs).values(id=job_id, owner_id=owner, trip_id=request.get("trip_id"),
                      task_type=request["task_type"], dedupe_key=dedupe, payload=payload))
            from .budgets import Budgets
            Budgets(self.engine).configure(c, scope_key="job:" + job_id, provider=self.provider, currency="USD",
                period_start=now, period_end=now + timedelta(days=7), cap_amount=Decimal(request["budget_amount"]))
            emit(c, {"id": job_id, "owner_id": owner}, "queued", {"task_type": request["task_type"]})
            return save_receipt(c, owner, key, shape, {"job_id": job_id, "status": "queued", "deduplicated": False})

    def claim(self, *, now=None):
        now = now or utcnow()
        with transaction(self.engine) as c:
            if c.dialect.name == "postgresql":
                c.execute(text("SELECT pg_advisory_xact_lock(hashtext(:provider_key))"),
                          {"provider_key": "trippy-claim:" + self.provider})
            active = c.execute(select(func.count()).select_from(s.research_jobs).where(
                s.research_jobs.c.status == "running", s.research_jobs.c.lease_until > now,
                s.research_jobs.c.payload["provider"].as_string() == self.provider)).scalar_one()
            if active >= self.max_concurrency:
                return None
            query = select(s.research_jobs).where(or_(
                and_(s.research_jobs.c.status == "queued", s.research_jobs.c.next_run_at <= now),
                and_(s.research_jobs.c.status == "running", s.research_jobs.c.lease_until <= now)))
            # A worker must not take jobs from a different configured provider.
            query = query.where(s.research_jobs.c.payload["provider"].as_string() == self.provider)
            jobs = c.execute(query.order_by(s.research_jobs.c.next_run_at, s.research_jobs.c.id)
                             .limit(20).with_for_update(skip_locked=True)).mappings().all()
            for found in jobs:
                job = dict(found)
                if job["status"] == "running":
                    # A crashed worker may have dispatched. Preserve all holds.
                    c.execute(update(s.usage_reservations).where(s.usage_reservations.c.job_id == job["id"],
                              s.usage_reservations.c.status == "reserved").values(status="uncertain"))
                    emit(c, job, "lease_expired", {"fence": job["fence"]})
                    pending = c.execute(select(s.usage_reservations.c.id).where(
                        s.usage_reservations.c.job_id == job["id"],
                        s.usage_reservations.c.status.in_(["uncertain", "reconciled"]))).first()
                    if pending:
                        c.execute(update(s.research_jobs).where(s.research_jobs.c.id == job["id"]).values(
                            status="failed", lease_token=None, lease_until=None))
                        emit(c, job, "failed", {"reason": "dispatch_requires_recovery"})
                        continue
                if job["attempt_count"] >= self.max_attempts:
                    c.execute(update(s.research_jobs).where(s.research_jobs.c.id == job["id"]).values(
                        status="dead_letter", lease_token=None, lease_until=None))
                    emit(c, job, "dead_letter", {"reason": "retry_limit"})
                    continue
                lease = Lease(job["id"], str(uuid4()), job["fence"] + 1)
                values = {"status": "running", "lease_token": lease.token, "fence": lease.fence,
                          "lease_until": now + timedelta(seconds=self.lease_seconds), "attempt_count": job["attempt_count"] + 1}
                c.execute(update(s.research_jobs).where(s.research_jobs.c.id == job["id"]).values(**values))
                job.update(values)
                emit(c, job, "running", {"attempt": job["attempt_count"], "fence": lease.fence})
                return job, lease
        return None

    def heartbeat(self, lease):
        with transaction(self.engine) as c:
            job = row(c, s.research_jobs, s.research_jobs.c.id == lease.job_id, lock=True)
            now = utcnow()
            require_lease(job, lease, now)
            c.execute(update(s.research_jobs).where(s.research_jobs.c.id == lease.job_id).values(
                lease_until=now + timedelta(seconds=self.lease_seconds)))

    def finish(self, lease, result):
        with transaction(self.engine) as c:
            job = row(c, s.research_jobs, s.research_jobs.c.id == lease.job_id, lock=True)
            require_lease(job, lease, utcnow())
            applied = self.repository.apply_proposals(c, job, result)
            c.execute(insert(s.job_results).values(job_id=job["id"], owner_id=job["owner_id"], fence=lease.fence,
                      result={"summary": result.summary, "proposals": result.model_dump(mode="json")["proposals"], "applied": applied}))
            c.execute(update(s.research_jobs).where(s.research_jobs.c.id == job["id"]).values(
                status="completed", lease_token=None, lease_until=None))
            emit(c, job, "completed", {"applied": applied})

    def fail(self, lease, reason, *, retry=False):
        with transaction(self.engine) as c:
            job = row(c, s.research_jobs, s.research_jobs.c.id == lease.job_id, lock=True)
            require_lease(job, lease, utcnow())
            status = "queued" if retry and job["attempt_count"] < self.max_attempts else "dead_letter" if retry else "failed"
            c.execute(update(s.research_jobs).where(s.research_jobs.c.id == job["id"]).values(
                status=status, lease_token=None, lease_until=None,
                next_run_at=utcnow() + timedelta(seconds=min(60, 2 ** job["attempt_count"]))))
            emit(c, job, status, {"reason": reason})

    def cancel(self, owner, job_id, key):
        shape = {"operation": "cancel", "job_id": job_id}
        with transaction(self.engine) as c:
            cached = receipt(c, owner, key, shape)
            if cached is not None:
                return cached
            job = row(c, s.research_jobs, (s.research_jobs.c.id == job_id) & (s.research_jobs.c.owner_id == owner), lock=True)
            if job["status"] in {"queued", "running"}:
                c.execute(update(s.research_jobs).where(s.research_jobs.c.id == job_id).values(
                    status="cancelled", lease_token=None, lease_until=None, fence=job["fence"] + 1))
                emit(c, job, "cancelled", {"billing_status": "pending_if_dispatched"})
                job["status"] = "cancelled"
            return save_receipt(c, owner, key, shape, {"job_id": job_id, "status": job["status"]})

    def get(self, owner, job_id):
        with self.engine.connect() as c:
            job = row(c, s.research_jobs, (s.research_jobs.c.id == job_id) & (s.research_jobs.c.owner_id == owner))
            # Do not expose internal lease tokens, provider payload or prompts.
            output = {k: job[k] for k in ("id", "trip_id", "task_type", "status", "attempt_count", "created_at")}
            result = c.execute(select(s.job_results.c.result).where(s.job_results.c.job_id == job_id,
                s.job_results.c.owner_id == owner)).scalar_one_or_none()
            output["result"] = result
            return output

    def events(self, owner, job_id, after, limit):
        with self.engine.connect() as c:
            row(c, s.research_jobs, (s.research_jobs.c.id == job_id) & (s.research_jobs.c.owner_id == owner))
            return [dict(r) for r in c.execute(select(s.job_events.c.sequence, s.job_events.c.kind,
                s.job_events.c.payload, s.job_events.c.created_at).where(s.job_events.c.job_id == job_id,
                s.job_events.c.owner_id == owner, s.job_events.c.sequence > after)
                .order_by(s.job_events.c.sequence).limit(limit)).mappings()]
