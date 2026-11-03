from datetime import date, datetime, time
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Request(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class NewTrip(Request):
    destination: str = Field(min_length=1, max_length=160)


class TripPatch(Request):
    expected_revision: int = Field(ge=0)
    arrival_date: date | None = None
    departure_date: date | None = None
    duration_days: int | None = Field(default=None, ge=1, le=365)
    date_mode: Literal["fixed", "flexible", "unknown"] | None = None


class SelectionMutation(Request):
    expected_trip_revision: int = Field(ge=0)
    expected_revision: int = Field(ge=0)
    action: Literal["select", "lock", "unlock", "undo"]
    candidate_id: UUID | None = None
    history_revision: int | None = Field(default=None, ge=0)

    @model_validator(mode="after")
    def action_fields(self):
        if (self.action == "select") != (self.candidate_id is not None):
            raise ValueError("Only select requires candidate_id")
        if (self.action == "undo") != (self.history_revision is not None):
            raise ValueError("Only undo requires history_revision")
        return self


class SlotMutation(Request):
    expected_trip_revision: int = Field(ge=0)
    expected_revision: int = Field(ge=0)
    starts_at: time | None = None
    duration_minutes: int | None = Field(default=None, ge=1, le=1440)
    is_scheduled: bool | None = None
    time_locked: bool | None = None
    order_locked: bool | None = None

    @model_validator(mode="after")
    def local_time(self):
        if self.starts_at is not None and self.starts_at.tzinfo is not None:
            raise ValueError("Slot times are local wall times without a UTC offset")
        for key in ("is_scheduled", "time_locked", "order_locked"):
            if key in self.model_fields_set and getattr(self, key) is None:
                raise ValueError("Slot flags cannot be null")
        return self


class DayOrderMutation(Request):
    expected_trip_revision: int = Field(ge=0)
    decision_ids: list[UUID] = Field(min_length=1, max_length=100)

    @model_validator(mode="after")
    def unique(self):
        if len(set(self.decision_ids)) != len(self.decision_ids):
            raise ValueError("Day order contains duplicate decisions")
        return self


class NewJob(Request):
    task_type: Literal["trip_research", "catalog_enrichment"]
    trip_id: UUID | None = None
    city_id: UUID | None = None
    expected_trip_revision: int | None = Field(default=None, ge=0)
    # A client may lower, never raise, the server's per-job ceiling.
    budget_amount: Decimal = Field(default=Decimal("0"), ge=0, max_digits=16, decimal_places=6)

    @model_validator(mode="after")
    def target(self):
        if self.task_type == "trip_research":
            if self.trip_id is None or self.expected_trip_revision is None or self.city_id is not None:
                raise ValueError("Trip research requires trip/revision only")
        elif self.city_id is None or self.trip_id is not None or self.expected_trip_revision is not None:
            raise ValueError("Catalog enrichment requires city only")
        return self


class BudgetConfiguration(Request):
    scope_key: str = Field(pattern=r"^(global|owner:[0-9a-f-]{36}|city:[0-9a-f-]{36}|trip:[0-9a-f-]{36}|job:[0-9a-f-]{36})$")
    provider: Literal["fake", "azure-luna"]
    currency: Literal["USD"] = "USD"
    period_start: datetime
    period_end: datetime
    cap_amount: Decimal = Field(ge=0, max_digits=16, decimal_places=6)

    @model_validator(mode="after")
    def interval(self):
        if self.period_start.utcoffset() is None or self.period_end.utcoffset() is None or self.period_end <= self.period_start:
            raise ValueError("A bounded timezone-aware budget period is required")
        return self


class Proposal(Request):
    decision_id: UUID
    candidate_id: UUID
    expected_revision: int = Field(ge=0)


class ProviderResult(Request):
    # No arbitrary source facts can be published by the Stage-2 preview worker.
    proposals: list[Proposal] = Field(default_factory=list, max_length=100)
    input_tokens: int = Field(ge=0, strict=True)
    output_tokens: int = Field(ge=0, strict=True)
    tool_calls: int = Field(ge=0, strict=True)
    summary: str = Field(default="", max_length=1000)

    @model_validator(mode="after")
    def unique_decisions(self):
        if len({p.decision_id for p in self.proposals}) != len(self.proposals):
            raise ValueError("Duplicate decision proposals")
        return self
