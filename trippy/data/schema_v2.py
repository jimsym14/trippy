"""Frozen Stage-2 additions; the released Stage-1 snapshot stays immutable."""

from sqlalchemy import (
    CheckConstraint, Column, DateTime, ForeignKey, ForeignKeyConstraint,
    Integer, MetaData, Numeric, String, Table, UniqueConstraint,
)

from .schema_v1 import metadata as initial, identity, created, json_type

metadata = MetaData(naming_convention=initial.naming_convention)
for table in initial.sorted_tables:
    table.to_metadata(metadata)

budget_accounts = Table(
    "budget_accounts", metadata, identity(),
    Column("scope_key", String(128), nullable=False),
    Column("provider", String(64), nullable=False), Column("currency", String(3), nullable=False),
    Column("period_start", DateTime(timezone=True), nullable=False),
    Column("period_end", DateTime(timezone=True), nullable=False),
    Column("cap_amount", Numeric(16, 6), nullable=False),
    Column("held_amount", Numeric(16, 6), nullable=False, server_default="0"),
    Column("spent_amount", Numeric(16, 6), nullable=False, server_default="0"),
    CheckConstraint("period_end > period_start", name="valid_period"),
    CheckConstraint("cap_amount >= 0 AND held_amount >= 0 AND spent_amount >= 0", name="nonnegative_amounts"),
    UniqueConstraint("scope_key", "provider", "currency", "period_start", "period_end"), created(),
)
reservation_allocations = Table(
    "reservation_allocations", metadata,
    Column("reservation_id", String(36), ForeignKey("usage_reservations.id"), primary_key=True),
    Column("budget_id", String(36), ForeignKey("budget_accounts.id"), primary_key=True),
)
mutation_receipts = Table(
    "mutation_receipts", metadata, identity(),
    Column("owner_id", String(36), ForeignKey("app_users.id"), nullable=False),
    Column("request_key", String(128), nullable=False), Column("fingerprint", String(64), nullable=False),
    Column("response", json_type, nullable=False),
    UniqueConstraint("owner_id", "request_key"), created(),
)
job_results = Table(
    "job_results", metadata, Column("job_id", String(36), primary_key=True),
    Column("owner_id", String(36), nullable=False), Column("fence", Integer, nullable=False),
    Column("result", json_type, nullable=False),
    ForeignKeyConstraint(["job_id", "owner_id"], ["research_jobs.id", "research_jobs.owner_id"]),
    CheckConstraint("fence > 0", name="positive_fence"), created(),
)

# Export current tables without importing stale Table objects into repositories.
globals().update(metadata.tables)
