"""Frozen Stage-3 inventory snapshots and import/identity provenance."""

from sqlalchemy import (
    Boolean, CheckConstraint, Column, DateTime, ForeignKey, Index, Integer,
    MetaData, Numeric, String, Table, Text, UniqueConstraint, false,
)
from .schema_v2 import metadata as previous
from .schema_v1 import identity, created, json_type, coordinate_checks, enum_check

metadata = MetaData(naming_convention=previous.naming_convention)
for table in previous.sorted_tables:
    table.to_metadata(metadata)

geography_references = Table(
    "geography_references", metadata, identity(),
    Column("geography_id", String(36), ForeignKey("geographies.id"), nullable=False),
    Column("source_id", String(36), ForeignKey("source_records.id"), nullable=False),
    Column("provider", String(32), nullable=False), Column("external_id", String(64), nullable=False),
    UniqueConstraint("provider", "external_id"), created(),
)
catalog_import_runs = Table(
    "catalog_import_runs", metadata, identity(),
    Column("geography_id", String(36), ForeignKey("geographies.id"), nullable=False),
    Column("catalog_version_id", String(36), ForeignKey("catalog_versions.id"), nullable=False, unique=True),
    Column("source_id", String(36), ForeignKey("source_records.id"), nullable=False),
    Column("provider", String(32), nullable=False), Column("dataset_version", String(64), nullable=False),
    Column("input_sha256", String(64), nullable=False), Column("scope_sha256", String(64), nullable=False),
    Column("input_records", Integer, nullable=False), Column("accepted_records", Integer, nullable=False),
    Column("rejected_records", Integer, nullable=False), Column("duplicate_records", Integer, nullable=False),
    Column("manifest", json_type, nullable=False), Column("report", json_type, nullable=False),
    UniqueConstraint("provider", "dataset_version", "geography_id", "input_sha256", "scope_sha256"),
    CheckConstraint("input_records >= 0 AND accepted_records >= 0 AND rejected_records >= 0 AND duplicate_records >= 0", name="nonnegative_counts"), created(),
    CheckConstraint("input_records = accepted_records + rejected_records + duplicate_records", name="count_conservation"),
)
catalog_snapshots = Table(
    "catalog_snapshots", metadata,
    Column("catalog_version_id", String(36), ForeignKey("catalog_versions.id"), primary_key=True),
    Column("entity_id", String(36), ForeignKey("entities.id"), primary_key=True),
    Column("source_id", String(36), ForeignKey("source_records.id"), nullable=False),
    Column("external_id", Text, nullable=False), Column("name", Text, nullable=False),
    Column("search_text", Text, nullable=False), Column("source_category", Text, nullable=False),
    Column("family", String(24), nullable=False), Column("area_key", String(32), nullable=False),
    Column("latitude", Numeric(10, 7), nullable=False), Column("longitude", Numeric(10, 7), nullable=False),
    Column("address", Text), Column("locality", Text), Column("website_url", Text),
    Column("confidence", Numeric(5, 4)), Column("operating_status", String(32)),
    Column("identity_status", String(24), nullable=False, server_default="source_identity"),
    Column("source_properties", json_type, nullable=False),
    Column("shortlist_rank", Integer), Column("is_enriched", Boolean, nullable=False, server_default=false()),
    UniqueConstraint("catalog_version_id", "external_id"), UniqueConstraint("catalog_version_id", "shortlist_rank"),
    CheckConstraint("confidence BETWEEN 0 AND 1", name="confidence_range"),
    CheckConstraint("shortlist_rank > 0", name="positive_rank"),
    enum_check("identity_status", ("source_identity", "review_needed")), *coordinate_checks(),
)
Index("ix_catalog_snapshots_scope_family_area", catalog_snapshots.c.catalog_version_id,
      catalog_snapshots.c.family, catalog_snapshots.c.area_key)
Index("ix_catalog_snapshots_search_text", catalog_snapshots.c.search_text)
Index("ix_catalog_snapshots_location", catalog_snapshots.c.catalog_version_id,
      catalog_snapshots.c.latitude, catalog_snapshots.c.longitude)
catalog_identity_conflicts = Table(
    "catalog_identity_conflicts", metadata, identity(),
    Column("catalog_version_id", String(36), ForeignKey("catalog_versions.id"), nullable=False),
    Column("first_entity_id", String(36), ForeignKey("entities.id"), nullable=False),
    Column("second_entity_id", String(36), ForeignKey("entities.id"), nullable=False),
    Column("evidence", json_type, nullable=False),
    UniqueConstraint("catalog_version_id", "first_entity_id", "second_entity_id"),
    CheckConstraint("first_entity_id < second_entity_id", name="ordered_distinct_pair"), created(),
)

globals().update(metadata.tables)
