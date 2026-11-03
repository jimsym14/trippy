"""Exact-decimal, multi-scope reservations. Unknown spend remains held."""

from dataclasses import dataclass
from datetime import timezone
from decimal import Decimal, ROUND_UP
from sqlalchemy import insert, select, update

from trippy.data import schema_v2 as s
from .common import DomainError, row, transaction, utcnow

UNIT = Decimal("0.000001")


@dataclass(frozen=True)
class Limits:
    input_tokens: int = 8000
    output_tokens: int = 2000
    tool_calls: int = 2

    def __post_init__(self):
        if any(type(v) is not int or v < 0 for v in (self.input_tokens, self.output_tokens, self.tool_calls)):
            raise ValueError("Finite nonnegative integer provider limits are required")


@dataclass(frozen=True)
class RateCard:
    provider: str = "fake"
    currency: str = "USD"
    input_per_million: Decimal = Decimal("0")
    output_per_million: Decimal = Decimal("0")
    per_tool_call: Decimal = Decimal("0")

    def __post_init__(self):
        for v in (self.input_per_million, self.output_per_million, self.per_tool_call):
            if not isinstance(v, Decimal) or not v.is_finite() or v < 0:
                raise ValueError("Verified finite Decimal rates are required")
        if self.currency != "USD":
            raise ValueError("Stage-2 budgets use one configured USD rate card")

    def cost(self, input_tokens, output_tokens, tool_calls):
        return ((Decimal(input_tokens) * self.input_per_million + Decimal(output_tokens) * self.output_per_million)
                / Decimal(1000000) + Decimal(tool_calls) * self.per_tool_call).quantize(UNIT, rounding=ROUND_UP)


class Budgets:
    def __init__(self, engine):
        self.engine = engine

    def configure(self, c, *, scope_key, provider, currency, period_start, period_end, cap_amount):
        if period_start.utcoffset() is None or period_end.utcoffset() is None or period_end <= period_start:
            raise ValueError("Budget periods require timezone-aware ordered boundaries")
        period_start, period_end = period_start.astimezone(timezone.utc), period_end.astimezone(timezone.utc)
        if not isinstance(cap_amount, Decimal) or not cap_amount.is_finite() or cap_amount < 0:
            raise ValueError("Budget cap must be a finite nonnegative Decimal")
        existing = c.execute(select(s.budget_accounts).where(
            s.budget_accounts.c.scope_key == scope_key, s.budget_accounts.c.provider == provider,
            s.budget_accounts.c.currency == currency, s.budget_accounts.c.period_start == period_start,
            s.budget_accounts.c.period_end == period_end).with_for_update()).mappings().first()
        if existing:
            if existing["cap_amount"] != cap_amount:
                raise DomainError("budget_period_already_configured")
            return dict(existing)
        result = c.execute(insert(s.budget_accounts).values(scope_key=scope_key, provider=provider,
                           currency=currency, period_start=period_start, period_end=period_end, cap_amount=cap_amount))
        return row(c, s.budget_accounts, s.budget_accounts.c.id == result.inserted_primary_key[0])

    def reserve(self, job, lease, rate, limits):
        amount = rate.cost(limits.input_tokens, limits.output_tokens, limits.tool_calls)
        key = f"job:{job['id']}:fence:{lease.fence}"
        now = utcnow()
        with transaction(self.engine) as c:
            current = row(c, s.research_jobs, s.research_jobs.c.id == job["id"], lock=True)
            from .queue import require_lease
            require_lease(current, lease, now)
            existing = c.execute(select(s.usage_reservations).where(
                s.usage_reservations.c.owner_id == job["owner_id"], s.usage_reservations.c.provider == rate.provider,
                s.usage_reservations.c.idempotency_key == key)).mappings().first()
            if existing:
                # A reserved/uncertain key is never permission to dispatch again.
                raise DomainError("dispatch_already_reserved")
            required = {"global", "owner:" + job["owner_id"], "job:" + job["id"]}
            scopes = set(required)
            if job["trip_id"]:
                scopes.add("trip:" + job["trip_id"])
            city_id = job["payload"].get("city_id") or job["payload"].get("snapshot", {}).get("geography_id")
            if city_id:
                scopes.add("city:" + city_id)
                if job["task_type"] == "catalog_enrichment":
                    required.add("city:" + city_id)
            accounts = list(c.execute(select(s.budget_accounts).where(
                s.budget_accounts.c.scope_key.in_(sorted(scopes)), s.budget_accounts.c.provider == rate.provider,
                s.budget_accounts.c.currency == rate.currency, s.budget_accounts.c.period_start <= now,
                s.budget_accounts.c.period_end > now).order_by(s.budget_accounts.c.id).with_for_update()).mappings())
            if not required.issubset({a["scope_key"] for a in accounts}):
                raise DomainError("budget_not_configured", 503)
            for account in accounts:
                changed = c.execute(update(s.budget_accounts).where(s.budget_accounts.c.id == account["id"],
                    s.budget_accounts.c.held_amount + s.budget_accounts.c.spent_amount + amount <= s.budget_accounts.c.cap_amount)
                    .values(held_amount=s.budget_accounts.c.held_amount + amount))
                if changed.rowcount != 1:
                    raise DomainError("budget_exhausted", 429)
            result = c.execute(insert(s.usage_reservations).values(owner_id=job["owner_id"], job_id=job["id"],
                               provider=rate.provider, currency=rate.currency, reserved_amount=amount, idempotency_key=key))
            reservation_id = result.inserted_primary_key[0]
            for account in accounts:
                c.execute(insert(s.reservation_allocations).values(reservation_id=reservation_id, budget_id=account["id"]))
            c.execute(insert(s.usage_ledger).values(owner_id=job["owner_id"], reservation_id=reservation_id,
                      entry_kind="reservation", amount=amount, currency=rate.currency))
            return reservation_id

    def settle(self, reservation_id, *, result=None, rate=None, uncertain=False, undispatched=False):
        if sum((result is not None, uncertain, undispatched)) != 1:
            raise ValueError("One settlement outcome is required")
        with transaction(self.engine) as c:
            reservation = row(c, s.usage_reservations, s.usage_reservations.c.id == reservation_id, lock=True)
            if result is not None:
                if rate is None or rate.provider != reservation["provider"] or rate.currency != reservation["currency"]:
                    raise ValueError("Settlement must use the reserved provider/currency")
                amount = rate.cost(result.input_tokens, result.output_tokens, result.tool_calls)
            else:
                amount = Decimal("0")
            if reservation["status"] in {"reconciled", "released"}:
                if result is not None and reservation["status"] == "reconciled" and reservation["actual_amount"] == amount:
                    return {"status": "reconciled", "overrun": amount > reservation["reserved_amount"]}
                if undispatched and reservation["status"] == "released":
                    return {"status": "released", "overrun": False}
                raise DomainError("settlement_conflict")
            if uncertain:
                c.execute(update(s.usage_reservations).where(s.usage_reservations.c.id == reservation_id).values(status="uncertain"))
                return {"status": "uncertain", "overrun": False}
            accounts = c.execute(select(s.budget_accounts).join(s.reservation_allocations,
                s.reservation_allocations.c.budget_id == s.budget_accounts.c.id).where(
                s.reservation_allocations.c.reservation_id == reservation_id).order_by(s.budget_accounts.c.id)
                .with_for_update()).mappings().all()
            for account in accounts:
                # Actual overrun is recorded fully rather than hidden/clamped.
                # spent+held > cap prevents any subsequent reservation.
                c.execute(update(s.budget_accounts).where(s.budget_accounts.c.id == account["id"]).values(
                    held_amount=s.budget_accounts.c.held_amount - reservation["reserved_amount"],
                    spent_amount=s.budget_accounts.c.spent_amount + amount))
            status = "released" if undispatched else "reconciled"
            c.execute(update(s.usage_reservations).where(s.usage_reservations.c.id == reservation_id).values(
                status=status, actual_amount=amount))
            counts = {} if result is None else {"input_tokens": result.input_tokens,
                "output_tokens": result.output_tokens, "tool_calls": result.tool_calls}
            c.execute(insert(s.usage_ledger).values(owner_id=reservation["owner_id"], reservation_id=reservation_id,
                      entry_kind="release" if undispatched else "actual", amount=amount,
                      currency=reservation["currency"], **counts))
            return {"status": status, "overrun": amount > reservation["reserved_amount"]}
