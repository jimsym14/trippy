"""Immutable Stage-1 schema snapshot used by Alembic revision 0001.

Core fields and ownership are relational. JSON is limited to source-specific
values, task/context payloads and explicitly separate legacy extension data.
No schema import opens a connection or creates tables.
"""

from uuid import uuid4

from sqlalchemy import (
    Boolean, CheckConstraint, Column, Date, DateTime, ForeignKey,
    ForeignKeyConstraint, Index, Integer, JSON, MetaData, Numeric, String,
    Table, Text, Time, UniqueConstraint, false, func, text,
)
from sqlalchemy.dialects.postgresql import JSONB


metadata = MetaData(naming_convention={
    "ix": "ix_%(table_name)s_%(column_0_name)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
})
json_type = JSON().with_variant(JSONB(), "postgresql")


def identity():
    return Column("id", String(36), primary_key=True, default=lambda: str(uuid4()))


def created():
    return Column("created_at", DateTime(timezone=True), nullable=False, server_default=func.now())


def payload(name, nullable=False):
    return Column(name, json_type, nullable=nullable)


def owner():
    return Column("owner_id", String(36), ForeignKey("app_users.id"), nullable=False)


def owned_key():
    return UniqueConstraint("id", "owner_id")


def scoped():
    """A nonnullable scope key makes private/shared composite FKs enforceable."""
    return [
        Column("owner_id", String(36), ForeignKey("app_users.id")),
        Column("scope_key", String(36), nullable=False),
        CheckConstraint("scope_key = COALESCE(owner_id, 'shared')", name="scope_matches_owner"),
        UniqueConstraint("id", "scope_key"),
    ]


def target():
    return [
        Column("entity_id", String(36), ForeignKey("entities.id")),
        Column("user_place_id", String(36)),
        ForeignKeyConstraint(["user_place_id", "owner_id"], ["user_places.id", "user_places.owner_id"]),
        CheckConstraint("(entity_id IS NOT NULL AND user_place_id IS NULL) OR "
                        "(entity_id IS NULL AND user_place_id IS NOT NULL AND owner_id IS NOT NULL)",
                        name="exactly_one_target"),
    ]


def enum_check(column, values):
    return CheckConstraint(f"{column} IN ({', '.join(repr(v) for v in values)})", name=f"{column}_values")


def coordinate_checks():
    return [
        CheckConstraint("latitude BETWEEN -90 AND 90", name="latitude_range"),
        CheckConstraint("longitude BETWEEN -180 AND 180", name="longitude_range"),
        CheckConstraint("(latitude IS NULL) = (longitude IS NULL)", name="coordinate_pair"),
    ]


app_users = Table("app_users", metadata, identity(), created())

geographies = Table(
    "geographies", metadata, identity(), Column("kind", String(16), nullable=False),
    Column("name", Text, nullable=False), Column("parent_id", String(36), ForeignKey("geographies.id")),
    Column("country_code", String(2)), Column("timezone", Text),
    Column("latitude", Numeric(10, 7)), Column("longitude", Numeric(10, 7)),
    enum_check("kind", ("continent", "country", "region", "city", "area")),
    CheckConstraint("parent_id IS NULL OR parent_id <> id", name="not_own_parent"),
    *coordinate_checks(), created(),
)
Index("ix_geographies_parent_kind", geographies.c.parent_id, geographies.c.kind)
geography_relations = Table(
    "geography_relations", metadata,
    Column("from_id", String(36), ForeignKey("geographies.id"), primary_key=True),
    Column("to_id", String(36), ForeignKey("geographies.id"), primary_key=True),
    Column("kind", String(24), primary_key=True),
    CheckConstraint("from_id <> to_id", name="different_geographies"),
)

catalog_versions = Table(
    "catalog_versions", metadata, identity(),
    Column("geography_id", String(36), ForeignKey("geographies.id"), nullable=False),
    Column("version", Integer, nullable=False), Column("published_at", DateTime(timezone=True)),
    Column("status", String(16), nullable=False, server_default="draft"),
    enum_check("status", ("draft", "published", "retired")),
    UniqueConstraint("geography_id", "version"), CheckConstraint("version > 0", name="positive_version"), created(),
)

entities = Table(
    "entities", metadata, identity(), Column("kind", String(24), nullable=False),
    Column("name", Text, nullable=False), Column("category", String(64), nullable=False),
    Column("geography_id", String(36), ForeignKey("geographies.id")),
    Column("address", Text), Column("latitude", Numeric(10, 7)), Column("longitude", Numeric(10, 7)),
    Column("official_url", Text), Column("timezone", Text),
    Column("publication_status", String(16), nullable=False, server_default="draft"),
    Column("catalog_version_id", String(36), ForeignKey("catalog_versions.id")),
    enum_check("kind", ("place", "activity", "brand", "dish", "experience", "transport", "ticket", "accommodation")),
    enum_check("publication_status", ("draft", "published", "retired")),
    *coordinate_checks(), created(),
)
Index("ix_entities_geo_category_status", entities.c.geography_id, entities.c.category, entities.c.publication_status)
entity_aliases = Table(
    "entity_aliases", metadata, Column("entity_id", String(36), ForeignKey("entities.id"), primary_key=True),
    Column("alias", Text, primary_key=True), Column("language", String(16), primary_key=True, server_default="und"),
)
entity_relations = Table(
    "entity_relations", metadata,
    Column("from_id", String(36), ForeignKey("entities.id"), primary_key=True),
    Column("to_id", String(36), ForeignKey("entities.id"), primary_key=True),
    Column("kind", String(48), primary_key=True),
    CheckConstraint("from_id <> to_id", name="different_entities"),
)
activities = Table(
    "activities", metadata, Column("entity_id", String(36), ForeignKey("entities.id"), primary_key=True),
    Column("base_geography_id", String(36), ForeignKey("geographies.id")),
    Column("duration_minutes", Integer), Column("duration_is_estimate", Boolean, nullable=False, server_default="true"),
    Column("walking_effort", String(24)), Column("seasonality_note", Text),
    CheckConstraint("duration_minutes > 0", name="positive_duration"),
)

source_policies = Table(
    "source_policies", metadata, identity(), Column("provider", String(64), nullable=False),
    Column("policy_version", String(32), nullable=False), Column("agreement_url", Text),
    Column("status", String(16), nullable=False, server_default="pending"),
    payload("allowed_fields"), Column("can_retain_raw", Boolean, nullable=False, server_default=false()),
    Column("can_use_in_prompt", Boolean, nullable=False, server_default=false()),
    Column("retention_seconds", Integer), Column("reviewed_at", DateTime(timezone=True)),
    enum_check("status", ("pending", "permitted", "restricted")),
    CheckConstraint("retention_seconds >= 0", name="nonnegative_retention"),
    UniqueConstraint("provider", "policy_version"), created(),
)
provider_entities = Table(
    "provider_entities", metadata, identity(), Column("provider", String(64), nullable=False),
    Column("external_id", Text, nullable=False), Column("entity_id", String(36), ForeignKey("entities.id"), nullable=False),
    Column("policy_id", String(36), ForeignKey("source_policies.id"), nullable=False),
    Column("match_status", String(16), nullable=False, server_default="candidate"),
    Column("dataset_version", Text), enum_check("match_status", ("candidate", "confirmed", "ambiguous")),
    UniqueConstraint("provider", "external_id"), created(),
)

trips = Table(
    "trips", metadata, identity(), owner(), owned_key(),
    Column("destination", Text, nullable=False), Column("geography_id", String(36), ForeignKey("geographies.id")),
    Column("date_mode", String(16), nullable=False, server_default="unknown"),
    Column("arrival_date", Date), Column("departure_date", Date), Column("duration_days", Integer),
    Column("timezone", Text), Column("revision", Integer, nullable=False, server_default="0"),
    enum_check("date_mode", ("fixed", "flexible", "unknown")),
    CheckConstraint("date_mode <> 'fixed' OR (arrival_date IS NOT NULL AND departure_date IS NOT NULL)", name="fixed_dates_required"),
    CheckConstraint("departure_date >= arrival_date", name="date_order"),
    CheckConstraint("duration_days > 0", name="positive_duration"),
    CheckConstraint("revision >= 0", name="nonnegative_revision"), created(),
)
user_places = Table(
    "user_places", metadata, identity(), owner(), owned_key(),
    Column("catalog_entity_id", String(36), ForeignKey("entities.id")),
    Column("name", Text, nullable=False), Column("category", String(64)), Column("address", Text), Column("description", Text),
    Column("latitude", Numeric(10, 7)), Column("longitude", Numeric(10, 7)),
    Column("official_url", Text), Column("notes", Text),
    Column("identity_status", String(16), nullable=False, server_default="candidate"),
    Column("legacy_key", Text), Column("origin_trip_id", String(36)),
    ForeignKeyConstraint(["origin_trip_id", "owner_id"], ["trips.id", "trips.owner_id"]),
    UniqueConstraint("owner_id", "origin_trip_id", "legacy_key"),
    enum_check("identity_status", ("candidate", "confirmed", "ambiguous", "not_found")),
    *coordinate_checks(), created(),
)
Index("ix_user_places_owner_name", user_places.c.owner_id, user_places.c.name)
user_place_tags = Table(
    "user_place_tags", metadata, Column("user_place_id", String(36), primary_key=True), owner(),
    Column("tag", Text, primary_key=True),
    ForeignKeyConstraint(["user_place_id", "owner_id"], ["user_places.id", "user_places.owner_id"]),
)
user_place_references = Table(
    "user_place_references", metadata, identity(), owner(), owned_key(),
    Column("user_place_id", String(36), nullable=False), Column("provider", String(64), nullable=False),
    Column("external_id", Text), Column("source_url", Text),
    Column("policy_id", String(36), ForeignKey("source_policies.id"), nullable=False),
    ForeignKeyConstraint(["user_place_id", "owner_id"], ["user_places.id", "user_places.owner_id"]),
    CheckConstraint("external_id IS NOT NULL OR source_url IS NOT NULL", name="reference_present"),
    UniqueConstraint("owner_id", "provider", "external_id"), created(),
)
research_runs = Table(
    "research_runs", metadata, identity(), owner(), owned_key(), Column("trip_id", String(36), nullable=False),
    Column("source_schema", String(64), nullable=False), Column("prompt_version", String(64)),
    Column("imported_at", DateTime(timezone=True), nullable=False, server_default=func.now()),
    Column("raw_storage_ref", Text), Column("raw_retention_until", DateTime(timezone=True)),
    Column("raw_policy_id", String(36), ForeignKey("source_policies.id")),
    Column("content_hash", String(64), nullable=False),
    ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]),
    CheckConstraint("raw_storage_ref IS NULL OR raw_policy_id IS NOT NULL", name="raw_requires_policy"),
    UniqueConstraint("trip_id", "content_hash"),
)

source_records = Table(
    "source_records", metadata, identity(), *scoped(),
    Column("policy_id", String(36), ForeignKey("source_policies.id"), nullable=False),
    Column("url", Text, nullable=False), Column("publisher", Text), Column("source_type", String(32)),
    Column("fetched_at", DateTime(timezone=True)), Column("checked_on", Date),
    Column("retention_until", DateTime(timezone=True)),
    Column("publication_status", String(16), nullable=False, server_default="draft"),
    enum_check("publication_status", ("draft", "published", "retired")), created(),
)
retrieval_references = Table(
    "retrieval_references", metadata, identity(), *scoped(),
    Column("source_id", String(36), nullable=False), Column("lookup_key", Text),
    Column("adapter_version", String(64), nullable=False), payload("requested_fields"),
    Column("refresh_after", DateTime(timezone=True)),
    ForeignKeyConstraint(["source_id", "scope_key"], ["source_records.id", "source_records.scope_key"]), created(),
)
observations = Table(
    "observations", metadata, identity(), *scoped(), *target(),
    Column("source_id", String(36), nullable=False), Column("research_run_id", String(36)),
    Column("field_key", String(64), nullable=False), payload("value", nullable=True),
    Column("unit", String(24)), Column("basis", Text), Column("observed_at", DateTime(timezone=True)),
    Column("checked_on", Date), Column("valid_from", DateTime(timezone=True)), Column("valid_until", DateTime(timezone=True)),
    Column("refresh_after", DateTime(timezone=True)), Column("retention_until", DateTime(timezone=True)),
    Column("verification_status", String(24), nullable=False, server_default="unverified"),
    Column("supersedes_id", String(36)),
    Column("publication_status", String(16), nullable=False, server_default="draft"),
    ForeignKeyConstraint(["source_id", "scope_key"], ["source_records.id", "source_records.scope_key"]),
    ForeignKeyConstraint(["supersedes_id", "scope_key"], ["observations.id", "observations.scope_key"]),
    ForeignKeyConstraint(["research_run_id", "owner_id"], ["research_runs.id", "research_runs.owner_id"]),
    CheckConstraint("research_run_id IS NULL OR owner_id IS NOT NULL", name="run_is_private"),
    CheckConstraint("valid_until >= valid_from", name="validity_order"),
    CheckConstraint("verification_status <> 'confirmed' OR observed_at IS NOT NULL OR checked_on IS NOT NULL", name="confirmed_has_check_time"),
    enum_check("verification_status", ("unverified", "confirmed", "unknown", "stale", "disputed", "not_checked")),
    enum_check("publication_status", ("draft", "published", "retired")), created(),
)
Index("ix_observations_target_field_time", observations.c.entity_id, observations.c.field_key, observations.c.observed_at)
Index("ix_observations_owner_place_field", observations.c.owner_id, observations.c.user_place_id, observations.c.field_key)


def fact_table(name, *columns):
    return Table(name, metadata, identity(), *scoped(), Column("observation_id", String(36), nullable=False),
                 ForeignKeyConstraint(["observation_id", "scope_key"], ["observations.id", "observations.scope_key"]),
                 UniqueConstraint("observation_id"), *columns)


rating_snapshots = fact_table(
    "rating_snapshots", Column("rating_value", Numeric(3, 2)),
    Column("rating_scale", Integer, nullable=False, server_default="5"), Column("platform", Text, nullable=False),
    Column("review_count", Integer),
    CheckConstraint("rating_scale = 5", name="five_star_scale"),
    CheckConstraint("rating_value BETWEEN 0 AND 5", name="rating_range"),
    CheckConstraint("review_count >= 0", name="nonnegative_count"),
)
opening_rules = fact_table(
    "opening_rules", Column("weekday", Integer, nullable=False), Column("opens_at", Time), Column("closes_at", Time),
    Column("closes_next_day", Boolean, nullable=False, server_default=false()), Column("is_closed", Boolean),
    CheckConstraint("weekday BETWEEN 0 AND 6", name="weekday_range"),
    CheckConstraint("is_closed IS NOT TRUE OR (opens_at IS NULL AND closes_at IS NULL)", name="closed_has_no_window"),
)
opening_exceptions = fact_table(
    "opening_exceptions", Column("local_date", Date, nullable=False), Column("opens_at", Time), Column("closes_at", Time),
    Column("status", String(24), nullable=False),
    enum_check("status", ("confirmed_open", "confirmed_closed", "candidate", "not_found", "not_checked")),
)
price_observations = fact_table(
    "price_observations", Column("amount_min", Numeric(14, 4)), Column("amount_max", Numeric(14, 4)),
    Column("currency", String(3), nullable=False), Column("price_basis", String(64), nullable=False),
    Column("is_estimate", Boolean, nullable=False, server_default=false()),
    CheckConstraint("amount_min >= 0 AND amount_max >= 0", name="nonnegative_price"),
    CheckConstraint("amount_max >= amount_min", name="price_order"),
    CheckConstraint("length(currency) = 3", name="currency_length"),
)
ticket_products = Table(
    "ticket_products", metadata, identity(), Column("entity_id", String(36), ForeignKey("entities.id"), nullable=False),
    Column("name", Text, nullable=False), Column("eligibility_note", Text), Column("official_url", Text),
    Column("eligibility_observation_id", String(36)),
    Column("eligibility_scope_key", String(36), nullable=False, server_default="shared"),
    CheckConstraint("eligibility_scope_key = 'shared'", name="eligibility_is_shared"),
    ForeignKeyConstraint(["eligibility_observation_id", "eligibility_scope_key"],
                         ["observations.id", "observations.scope_key"]), created(),
)
event_occurrences = Table(
    "event_occurrences", metadata, identity(), *scoped(), *target(),
    Column("starts_at", DateTime(timezone=True)), Column("ends_at", DateTime(timezone=True)),
    Column("status", String(24), nullable=False, server_default="candidate"),
    Column("observation_id", String(36)),
    ForeignKeyConstraint(["observation_id", "scope_key"], ["observations.id", "observations.scope_key"]),
    CheckConstraint("ends_at >= starts_at", name="event_time_order"),
    enum_check("status", ("candidate", "confirmed", "cancelled", "unpublished")), created(),
)
classifications = Table(
    "classifications", metadata, identity(), *scoped(), *target(),
    Column("dimension", String(64), nullable=False), Column("score", Numeric(5, 4)),
    Column("reason", Text), Column("model_version", Text), Column("is_estimate", Boolean, nullable=False, server_default="true"),
    Column("observation_id", String(36)),
    ForeignKeyConstraint(["observation_id", "scope_key"], ["observations.id", "observations.scope_key"]),
    CheckConstraint("score BETWEEN 0 AND 1", name="fit_range"), created(),
)

preference_templates = Table(
    "preference_templates", metadata, Column("template_key", String(64), primary_key=True),
    Column("version", Integer, primary_key=True), Column("language", String(16), primary_key=True),
    Column("instruction", Text, nullable=False), Column("status", String(16), nullable=False, server_default="draft"),
    enum_check("status", ("draft", "published", "retired")), CheckConstraint("version > 0", name="positive_version"),
)
discovery_concepts = Table(
    "discovery_concepts", metadata, identity(), Column("concept_key", String(64), nullable=False, unique=True),
    Column("parent_family", String(64), nullable=False), Column("geography_id", String(36), ForeignKey("geographies.id")),
    Column("label", Text, nullable=False), Column("template_key", String(64)), Column("template_version", Integer),
    Column("template_language", String(16)),
    ForeignKeyConstraint(["template_key", "template_version", "template_language"],
                         ["preference_templates.template_key", "preference_templates.version", "preference_templates.language"]),
    Column("publication_status", String(16), nullable=False, server_default="draft"),
    enum_check("publication_status", ("draft", "published", "retired")),
)
concept_entities = Table(
    "concept_entities", metadata, Column("concept_id", String(36), ForeignKey("discovery_concepts.id"), primary_key=True),
    Column("entity_id", String(36), ForeignKey("entities.id"), primary_key=True),
)
trip_preferences = Table(
    "trip_preferences", metadata, identity(), owner(), owned_key(), Column("trip_id", String(36), nullable=False),
    Column("preference_key", String(64), nullable=False), Column("concept_id", String(36), ForeignKey("discovery_concepts.id")),
    payload("value", nullable=True), Column("strength", String(16), nullable=False, server_default="prefer"),
    enum_check("strength", ("prefer", "must", "avoid", "unknown")),
    ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]),
    UniqueConstraint("trip_id", "preference_key"),
)
visit_history = Table(
    "visit_history", metadata, identity(), owner(), owned_key(), *target(),
    Column("visited_on", Date), Column("revisit_allowed", Boolean), Column("note", Text), created(),
)
trip_days = Table(
    "trip_days", metadata, identity(), owner(), owned_key(), Column("trip_id", String(36), nullable=False),
    Column("local_date", Date), Column("day_number", Integer, nullable=False), Column("theme", Text),
    Column("order_locked", Boolean, nullable=False, server_default=false()),
    ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]),
    UniqueConstraint("trip_id", "day_number"), CheckConstraint("day_number > 0", name="positive_day"),
    UniqueConstraint("id", "trip_id", "owner_id"),
)
trip_decisions = Table(
    "trip_decisions", metadata, identity(), owner(), owned_key(), Column("trip_id", String(36), nullable=False),
    Column("kind", String(24), nullable=False), Column("purpose", Text, nullable=False),
    Column("legacy_key", Text), Column("revision", Integer, nullable=False, server_default="0"),
    payload("context"), ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]),
    UniqueConstraint("trip_id", "legacy_key"), UniqueConstraint("id", "trip_id", "owner_id"),
    enum_check("kind", ("activity", "transport", "ticket", "accommodation")),
    CheckConstraint("revision >= 0", name="nonnegative_revision"), created(),
)
activity_slots = Table(
    "activity_slots", metadata, Column("decision_id", String(36), primary_key=True), owner(),
    Column("trip_id", String(36), nullable=False), Column("day_id", String(36), nullable=False),
    Column("position", Integer, nullable=False), Column("starts_at", Time), Column("duration_minutes", Integer),
    Column("is_scheduled", Boolean, nullable=False, server_default="true"),
    Column("period", String(16)), Column("time_locked", Boolean, nullable=False, server_default=false()),
    Column("order_locked", Boolean, nullable=False, server_default=false()),
    ForeignKeyConstraint(["decision_id", "trip_id", "owner_id"], ["trip_decisions.id", "trip_decisions.trip_id", "trip_decisions.owner_id"]),
    ForeignKeyConstraint(["day_id", "trip_id", "owner_id"], ["trip_days.id", "trip_days.trip_id", "trip_days.owner_id"]),
    CheckConstraint("position >= 0", name="nonnegative_position"),
    CheckConstraint("duration_minutes > 0", name="positive_duration"),
)
decision_option_sets = Table(
    "decision_option_sets", metadata, identity(), owner(), owned_key(), Column("decision_id", String(36), nullable=False),
    Column("version", Integer, nullable=False), payload("retrieval_context"),
    Column("completeness", String(16), nullable=False, server_default="partial"),
    ForeignKeyConstraint(["decision_id", "owner_id"], ["trip_decisions.id", "trip_decisions.owner_id"]),
    UniqueConstraint("id", "decision_id", "owner_id"), UniqueConstraint("decision_id", "version"),
    CheckConstraint("version > 0", name="positive_version"), created(),
)
decision_candidates = Table(
    "decision_candidates", metadata, identity(), owner(), owned_key(), Column("decision_id", String(36), nullable=False),
    Column("option_set_id", String(36), nullable=False), *target(),
    Column("score", Numeric(8, 4)), Column("reason", Text),
    Column("eligibility_status", String(24), nullable=False, server_default="not_checked"),
    ForeignKeyConstraint(["option_set_id", "decision_id", "owner_id"],
                         ["decision_option_sets.id", "decision_option_sets.decision_id", "decision_option_sets.owner_id"]),
    UniqueConstraint("id", "decision_id", "owner_id"),
    UniqueConstraint("option_set_id", "entity_id"), UniqueConstraint("option_set_id", "user_place_id"),
    enum_check("eligibility_status", ("not_checked", "candidate", "eligible", "ineligible", "conflict")), created(),
)
decision_selections = Table(
    "decision_selections", metadata, Column("decision_id", String(36), primary_key=True), owner(),
    Column("selected_candidate_id", String(36)), Column("suggested_candidate_id", String(36)),
    Column("selection_owner", String(16), nullable=False, server_default="ai"),
    Column("selection_locked", Boolean, nullable=False, server_default=false()),
    Column("revision", Integer, nullable=False, server_default="0"), Column("conflict_reason", Text),
    ForeignKeyConstraint(["decision_id", "owner_id"], ["trip_decisions.id", "trip_decisions.owner_id"]),
    ForeignKeyConstraint(["selected_candidate_id", "decision_id", "owner_id"],
                         ["decision_candidates.id", "decision_candidates.decision_id", "decision_candidates.owner_id"]),
    ForeignKeyConstraint(["suggested_candidate_id", "decision_id", "owner_id"],
                         ["decision_candidates.id", "decision_candidates.decision_id", "decision_candidates.owner_id"]),
    enum_check("selection_owner", ("user", "ai")),
    CheckConstraint("revision >= 0", name="nonnegative_revision"),
    CheckConstraint("selection_locked IS NOT TRUE OR selection_owner = 'user'", name="lock_is_user_owned"),
    CheckConstraint("selection_locked IS NOT TRUE OR selected_candidate_id IS NOT NULL", name="lock_has_selection"),
)
selection_history = Table(
    "selection_history", metadata, identity(), owner(), Column("decision_id", String(36), nullable=False),
    Column("candidate_id", String(36)), Column("revision", Integer, nullable=False),
    Column("actor", String(16), nullable=False), Column("selection_locked", Boolean, nullable=False),
    ForeignKeyConstraint(["decision_id", "owner_id"], ["trip_decisions.id", "trip_decisions.owner_id"]),
    ForeignKeyConstraint(["candidate_id", "decision_id", "owner_id"],
                         ["decision_candidates.id", "decision_candidates.decision_id", "decision_candidates.owner_id"]),
    UniqueConstraint("decision_id", "revision"), created(),
)
user_reactions = Table(
    "user_reactions", metadata, identity(), owner(), Column("trip_id", String(36), nullable=False),
    Column("legacy_item_key", Text, nullable=False), Column("reaction", String(32), nullable=False),
    ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]), UniqueConstraint("trip_id", "legacy_item_key"),
)
user_overrides = Table(
    "user_overrides", metadata, identity(), owner(), Column("trip_id", String(36), nullable=False),
    Column("decision_id", String(36)), Column("legacy_item_key", Text), Column("field_key", String(64), nullable=False),
    payload("value", nullable=True),
    ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]),
    ForeignKeyConstraint(["decision_id", "trip_id", "owner_id"],
                         ["trip_decisions.id", "trip_decisions.trip_id", "trip_decisions.owner_id"]), created(),
)
bookings = Table(
    "bookings", metadata, identity(), owner(), Column("trip_id", String(36), nullable=False),
    Column("decision_id", String(36)), Column("status", String(24), nullable=False), Column("reference", Text),
    ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]),
    ForeignKeyConstraint(["decision_id", "trip_id", "owner_id"],
                         ["trip_decisions.id", "trip_decisions.trip_id", "trip_decisions.owner_id"]),
    enum_check("status", ("user_reported", "confirmed", "cancelled")), created(),
)
cost_lines = Table(
    "cost_lines", metadata, identity(), owner(), Column("trip_id", String(36), nullable=False),
    Column("title", Text, nullable=False), Column("amount", Numeric(14, 4)), Column("currency", String(3)),
    Column("basis", String(24), nullable=False), Column("quantity", Numeric(10, 4), nullable=False, server_default="1"),
    Column("origin", String(24), nullable=False),
    ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]),
    CheckConstraint("amount >= 0", name="nonnegative_cost"), CheckConstraint("quantity > 0", name="positive_quantity"), created(),
)
legacy_migration_state = Table(
    "legacy_migration_state", metadata, Column("trip_id", String(36), primary_key=True), owner(),
    Column("source_hash", String(64), nullable=False), Column("adapter_version", Integer, nullable=False),
    payload("id_map"), payload("app_owned_extensions"), Column("backup_ref", Text),
    ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]), created(),
)
research_extensions = Table(
    "research_extensions", metadata, identity(), owner(), Column("research_run_id", String(36), nullable=False),
    Column("record_key", Text, nullable=False), payload("value"),
    Column("policy_id", String(36), ForeignKey("source_policies.id"), nullable=False),
    Column("retention_until", DateTime(timezone=True)),
    ForeignKeyConstraint(["research_run_id", "owner_id"], ["research_runs.id", "research_runs.owner_id"]),
    UniqueConstraint("research_run_id", "record_key"),
)

research_jobs = Table(
    "research_jobs", metadata, identity(), owner(), owned_key(), Column("trip_id", String(36)),
    Column("task_type", String(48), nullable=False), Column("dedupe_key", String(128), nullable=False), payload("payload"),
    Column("status", String(24), nullable=False, server_default="queued"),
    Column("next_run_at", DateTime(timezone=True), nullable=False, server_default=func.now()),
    Column("lease_until", DateTime(timezone=True)), Column("lease_token", String(36)),
    Column("fence", Integer, nullable=False, server_default="0"), Column("attempt_count", Integer, nullable=False, server_default="0"),
    ForeignKeyConstraint(["trip_id", "owner_id"], ["trips.id", "trips.owner_id"]),
    CheckConstraint("fence >= 0 AND attempt_count >= 0", name="nonnegative_counters"),
    enum_check("status", ("queued", "running", "completed", "failed", "cancelled", "dead_letter")), created(),
)
Index("uq_research_jobs_active_dedupe", research_jobs.c.owner_id, research_jobs.c.dedupe_key, unique=True,
      postgresql_where=text("status IN ('queued', 'running')"), sqlite_where=text("status IN ('queued', 'running')"))
Index("ix_research_jobs_queue", research_jobs.c.status, research_jobs.c.next_run_at)
job_events = Table(
    "job_events", metadata, identity(), owner(), Column("job_id", String(36), nullable=False),
    Column("sequence", Integer, nullable=False), Column("kind", String(48), nullable=False), payload("payload"),
    ForeignKeyConstraint(["job_id", "owner_id"], ["research_jobs.id", "research_jobs.owner_id"]),
    UniqueConstraint("job_id", "sequence"), CheckConstraint("sequence > 0", name="positive_sequence"), created(),
)
usage_reservations = Table(
    "usage_reservations", metadata, identity(), owner(), owned_key(), Column("job_id", String(36)),
    Column("provider", String(64), nullable=False), Column("currency", String(3), nullable=False),
    Column("reserved_amount", Numeric(16, 6), nullable=False), Column("actual_amount", Numeric(16, 6)),
    Column("idempotency_key", String(128), nullable=False),
    Column("status", String(24), nullable=False, server_default="reserved"),
    ForeignKeyConstraint(["job_id", "owner_id"], ["research_jobs.id", "research_jobs.owner_id"]),
    UniqueConstraint("owner_id", "provider", "idempotency_key"),
    CheckConstraint("reserved_amount >= 0 AND actual_amount >= 0", name="nonnegative_usage"),
    enum_check("status", ("reserved", "reconciled", "released", "uncertain")), created(),
)
usage_ledger = Table(
    "usage_ledger", metadata, identity(), owner(), Column("reservation_id", String(36), nullable=False),
    Column("entry_kind", String(24), nullable=False), Column("amount", Numeric(16, 6), nullable=False),
    Column("currency", String(3), nullable=False), Column("input_tokens", Integer), Column("output_tokens", Integer),
    Column("tool_calls", Integer),
    ForeignKeyConstraint(["reservation_id", "owner_id"], ["usage_reservations.id", "usage_reservations.owner_id"]),
    UniqueConstraint("reservation_id", "entry_kind"),
    CheckConstraint("input_tokens >= 0 AND output_tokens >= 0 AND tool_calls >= 0", name="nonnegative_usage_counts"), created(),
)
