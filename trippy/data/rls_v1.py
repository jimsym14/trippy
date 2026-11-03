"""Frozen PostgreSQL/Supabase RLS and spatial DDL for revision 0001.

No authenticated client receives catalog or queue/usage write permissions.
The Stage-2 verified backend still performs ownership/revision checks.
"""

from .schema_v1 import metadata


SCOPED_FACTS = {"rating_snapshots", "opening_rules", "opening_exceptions", "price_observations"}


def shared_predicate(table):
    name = table.name
    if name == "source_records":
        return ("publication_status = 'published' AND EXISTS (SELECT 1 FROM source_policies p "
                "WHERE p.id = source_records.policy_id AND p.status = 'permitted')")
    if name == "concept_entities":
        return ("EXISTS (SELECT 1 FROM entities e WHERE e.id = concept_entities.entity_id AND e.publication_status = 'published') "
                "AND EXISTS (SELECT 1 FROM discovery_concepts c WHERE c.id = concept_entities.concept_id AND c.publication_status = 'published')")
    if "publication_status" in table.c:
        return "publication_status = 'published'"
    if name == "catalog_versions":
        return "status = 'published'"
    if name == "preference_templates":
        return "status = 'published'"
    if name in {"entity_aliases", "activities", "provider_entities", "ticket_products", "concept_entities"}:
        return f"EXISTS (SELECT 1 FROM entities e WHERE e.id = {name}.entity_id AND e.publication_status = 'published')"
    if name == "entity_relations":
        return ("EXISTS (SELECT 1 FROM entities e WHERE e.id = entity_relations.from_id AND e.publication_status = 'published') "
                "AND EXISTS (SELECT 1 FROM entities e WHERE e.id = entity_relations.to_id AND e.publication_status = 'published')")
    if name == "source_policies":
        return "status = 'permitted'"
    return "true"  # Public geography hierarchy/relations contain no user state.


def scoped_shared_predicate(table):
    name = table.name
    if name in SCOPED_FACTS or name in {"event_occurrences", "classifications"}:
        return (f"EXISTS (SELECT 1 FROM observations o WHERE o.id = {name}.observation_id "
                "AND o.scope_key = 'shared' AND o.publication_status = 'published')")
    if name == "retrieval_references":
        return ("EXISTS (SELECT 1 FROM source_records s WHERE s.id = retrieval_references.source_id "
                "AND s.scope_key = 'shared' AND s.publication_status = 'published')")
    if name == "observations":
        return ("publication_status = 'published' AND EXISTS (SELECT 1 FROM entities e "
                "WHERE e.id = observations.entity_id AND e.publication_status = 'published') "
                "AND EXISTS (SELECT 1 FROM source_records s WHERE s.id = observations.source_id "
                "AND s.scope_key = 'shared' AND s.publication_status = 'published')")
    return shared_predicate(table)


def statements():
    output = []
    for table in metadata.sorted_tables:
        name = table.name
        output += [f'ALTER TABLE "{name}" ENABLE ROW LEVEL SECURITY',
                   f'ALTER TABLE "{name}" FORCE ROW LEVEL SECURITY',
                   f'REVOKE ALL ON "{name}" FROM anon',
                   f'REVOKE ALL ON "{name}" FROM authenticated',
                   f'GRANT SELECT ON "{name}" TO authenticated',
                   f'GRANT ALL ON "{name}" TO service_role']
        if name == "app_users":
            predicate = "id = (SELECT auth.uid())::text"
        elif "scope_key" in table.c:
            predicate = ("owner_id = (SELECT auth.uid())::text OR "
                         f"(owner_id IS NULL AND {scoped_shared_predicate(table)})")
        elif "owner_id" in table.c:
            predicate = "owner_id = (SELECT auth.uid())::text"
        else:
            predicate = shared_predicate(table)
        if "retention_until" in table.c:
            predicate = f"({predicate}) AND (retention_until IS NULL OR retention_until > CURRENT_TIMESTAMP)"
        if name in SCOPED_FACTS:
            predicate = (f"({predicate}) AND EXISTS (SELECT 1 FROM observations parent "
                         f"WHERE parent.id = {name}.observation_id AND parent.scope_key = {name}.scope_key)")
        output.append(f'CREATE POLICY read_visible ON "{name}" FOR SELECT TO authenticated USING ({predicate})')
        # Stage 1 deliberately exposes only reads. Client mutations go through
        # verified Stage-2 backend transactions; there is no public write bypass.
    return output


SPATIAL_DDL = """
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;
DO $spatial$
DECLARE spatial_schema text;
BEGIN
  SELECT n.nspname INTO spatial_schema FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'postgis';
  EXECUTE format('CREATE INDEX ix_entities_location_gist ON entities USING gist (%I.ST_SetSRID(%I.ST_MakePoint(longitude::double precision, latitude::double precision), 4326)) WHERE latitude IS NOT NULL', spatial_schema, spatial_schema);
  EXECUTE format('CREATE INDEX ix_user_places_location_gist ON user_places USING gist (%I.ST_SetSRID(%I.ST_MakePoint(longitude::double precision, latitude::double precision), 4326)) WHERE latitude IS NOT NULL', spatial_schema, spatial_schema);
END; $spatial$;
CREATE INDEX ix_entities_name_fts ON entities USING gin (to_tsvector('simple', name));
"""
