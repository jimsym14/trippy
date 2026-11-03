"""Versioned internal trip overlay; source facts and app-owned state stay separate."""

from datetime import date
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Record(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)


class Coordinate(Record):
    latitude: float | None = Field(default=None, ge=-90, le=90, strict=True)
    longitude: float | None = Field(default=None, ge=-180, le=180, strict=True)
    status: str = "unknown"

    @model_validator(mode="after")
    def pair(self):
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("Coordinates must be a complete pair or unknown")
        return self


class PrivatePlace(Record):
    id: UUID
    legacy_id: str
    name: str
    category: str
    address: str | None = None
    official_url: str | None = None
    coordinates: Coordinate = Field(default_factory=Coordinate)
    coordinate_extensions: dict[str, Any] = Field(default_factory=dict)
    identity_status: Literal["candidate", "confirmed", "ambiguous", "not_found"] = "candidate"
    description: str | None = None
    tags: list[str] = Field(default_factory=list)
    legacy_fields: dict[str, Any] = Field(default_factory=dict)


class ImportedSource(Record):
    id: UUID
    legacy_id: str
    url: str
    publisher: str | None = None
    checked_on: date | None = None
    legacy_fields: dict[str, Any] = Field(default_factory=dict)


class ImportedClaim(Record):
    id: UUID
    user_place_id: UUID
    field_key: str
    value: Any
    source_ids: list[UUID] = Field(default_factory=list)
    checked_on: date | None = None
    verification_status: Literal["unverified", "unknown", "not_checked"] = "unverified"


class Day(Record):
    id: UUID
    legacy_key: str
    local_date: date | None = None
    day_number: int = Field(ge=1)
    theme: str | None = None
    order_locked: bool = False
    legacy_fields: dict[str, Any] = Field(default_factory=dict)


class Candidate(Record):
    id: UUID
    user_place_id: UUID | None = None
    entity_id: UUID | None = None
    eligibility_status: Literal["not_checked", "candidate", "eligible", "ineligible", "conflict"] = "not_checked"

    @model_validator(mode="after")
    def target(self):
        if (self.user_place_id is None) == (self.entity_id is None):
            raise ValueError("A candidate must reference exactly one private place or catalog entity")
        return self


class Decision(Record):
    id: UUID
    legacy_key: str
    kind: Literal["activity", "transport", "ticket", "accommodation"] = "activity"
    purpose: str
    day_id: UUID | None = None
    position: int = Field(default=0, ge=0)
    is_scheduled: bool = True
    time: str | None = None
    duration_minutes: int | None = Field(default=None, gt=0)
    period: str | None = None
    time_locked: bool = False
    order_locked: bool = False
    option_set_id: UUID
    candidates: list[Candidate] = Field(default_factory=list)
    selected_candidate_id: UUID | None = None
    suggested_candidate_id: UUID | None = None
    selection_owner: Literal["ai", "user"] = "ai"
    selection_locked: bool = False
    revision: int = Field(default=0, ge=0)
    context: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def selection_refs(self):
        candidate_ids = {candidate.id for candidate in self.candidates}
        if len(candidate_ids) != len(self.candidates):
            raise ValueError("Duplicate decision candidates")
        if len({(c.user_place_id, c.entity_id) for c in self.candidates}) != len(self.candidates):
            raise ValueError("Duplicate candidate targets")
        for reference in (self.selected_candidate_id, self.suggested_candidate_id):
            if reference is not None and reference not in candidate_ids:
                raise ValueError("Selection must reference this decision's candidate pool")
        if self.selection_locked and (self.selection_owner != "user" or self.selected_candidate_id is None):
            raise ValueError("A lock requires a user-owned selection")
        return self


class NormalizedTrip(Record):
    schema_version: Literal["trippy-trip-v2"] = "trippy-trip-v2"
    adapter_version: int = Field(default=1, ge=1)
    id: UUID
    owner_id: UUID
    legacy_trip_key: str = Field(min_length=1)
    destination: str
    date_mode: Literal["fixed", "flexible", "unknown"] = "unknown"
    arrival_date: date | None = None
    departure_date: date | None = None
    brief: dict[str, Any] = Field(default_factory=dict)
    places: list[PrivatePlace] = Field(default_factory=list)
    catalog_entity_ids: list[UUID] = Field(default_factory=list)
    sources: list[ImportedSource] = Field(default_factory=list)
    claims: list[ImportedClaim] = Field(default_factory=list)
    days: list[Day] = Field(default_factory=list)
    decisions: list[Decision] = Field(default_factory=list)
    app_owned_state: dict[str, Any] = Field(default_factory=dict)
    legacy_modules: dict[str, Any] = Field(default_factory=dict)
    id_map: dict[str, str] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)
    source_hash: str = Field(pattern="^[a-f0-9]{64}$")

    @model_validator(mode="after")
    def references(self):
        place_ids = {p.id for p in self.places}
        day_ids = {d.id for d in self.days}
        source_ids = {s.id for s in self.sources}
        if len(set(self.catalog_entity_ids)) != len(self.catalog_entity_ids):
            raise ValueError("Duplicate canonical entity references")
        for collection in (self.places, self.sources, self.days, self.decisions, self.claims):
            if len({row.id for row in collection}) != len(collection):
                raise ValueError("Duplicate normalized IDs")
        for decision in self.decisions:
            if decision.day_id is not None and decision.day_id not in day_ids:
                raise ValueError("Unknown decision day")
            if any((c.user_place_id is not None and c.user_place_id not in place_ids) or
                   (c.entity_id is not None and c.entity_id not in self.catalog_entity_ids)
                   for c in decision.candidates):
                raise ValueError("Unknown decision place")
        for claim in self.claims:
            if claim.user_place_id not in place_ids or any(s not in source_ids for s in claim.source_ids):
                raise ValueError("Unknown claim reference")
        if self.date_mode == "fixed" and (self.arrival_date is None or self.departure_date is None):
            raise ValueError("Fixed trip requires dates")
        if self.arrival_date and self.departure_date and self.departure_date < self.arrival_date:
            raise ValueError("Departure precedes arrival")
        return self
