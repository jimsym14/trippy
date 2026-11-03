"""Version/policy-aware shared catalog search and atomic local publication."""

from math import cos, radians
from datetime import timezone
from sqlalchemy import and_, bindparam, func, select, update

from trippy.backend.common import DomainError, row, transaction, utcnow
from trippy.backend.repository import receipt, save_receipt
from trippy.data import schema_v3 as s
from .importer import batches
from .normalize import distance_m, normalize_text


def visible_query():
    return select(s.catalog_snapshots, s.catalog_versions.c.geography_id,
                  s.source_records.c.url.label("source_url"), s.source_records.c.fetched_at,
                  s.source_policies.c.allowed_fields).join(s.catalog_versions,
                  s.catalog_versions.c.id == s.catalog_snapshots.c.catalog_version_id).join(s.source_records,
                  s.source_records.c.id == s.catalog_snapshots.c.source_id).join(s.source_policies,
                  s.source_policies.c.id == s.source_records.c.policy_id).join(s.entities,
                  s.entities.c.id == s.catalog_snapshots.c.entity_id).where(
                  s.catalog_versions.c.status == "published", s.entities.c.publication_status == "published",
                  s.source_records.c.owner_id.is_(None), s.source_records.c.scope_key == "shared",
                  s.source_records.c.publication_status == "published", s.source_policies.c.status == "permitted",
                  s.source_policies.c.can_retain_raw.is_(True),
                  (s.source_records.c.retention_until.is_(None) | (s.source_records.c.retention_until > utcnow())))


class Catalog:
    def __init__(self, engine):
        self.engine = engine

    def search(self, city_id, *, query="", family=None, shortlisted_only=False, after=None, limit=30,
               latitude=None, longitude=None, radius_m=2000):
        statement = visible_query().where(s.catalog_versions.c.geography_id == city_id)
        statement = statement.where(s.catalog_snapshots.c.operating_status.is_(None) |
                                    (s.catalog_snapshots.c.operating_status != "permanently_closed"))
        if query:
            term = normalize_text(query).replace("\\","\\\\").replace("%","\\%").replace("_","\\_")
            if not term:
                raise DomainError("search_text_required",422)
            statement = statement.where(s.catalog_snapshots.c.search_text.like("%"+term+"%",escape="\\"))
        if family:
            statement = statement.where(s.catalog_snapshots.c.family == family)
        if shortlisted_only:
            statement = statement.where(s.catalog_snapshots.c.shortlist_rank.is_not(None))
        if after:
            statement = statement.where(s.catalog_snapshots.c.entity_id > after)
        if latitude is not None:
            delta_lat = radius_m/111000
            delta_lon = radius_m/(111000*max(.01,cos(radians(latitude))))
            statement = statement.where(s.catalog_snapshots.c.latitude.between(latitude-delta_lat,latitude+delta_lat),
                                        s.catalog_snapshots.c.longitude.between(longitude-delta_lon,longitude+delta_lon))
        items, cursor = [], after
        with self.engine.connect() as c:
            # Scan bounded chunks for exact-radius and policy filtering. Cursor
            # advances over examined rows, including filtered-out source records.
            examined = 0
            while len(items) < limit and examined < 1000:
                page = statement
                if cursor:
                    page = page.where(s.catalog_snapshots.c.entity_id > cursor)
                values = c.execute(page.order_by(s.catalog_snapshots.c.entity_id).limit(min(100,1000-examined))).mappings().all()
                if not values:
                    return {"items":items,"next_cursor":None}
                for value in values:
                    examined += 1
                    cursor = value["entity_id"]
                    if not {"name","coordinates","category"}.issubset(value["allowed_fields"]):
                        continue
                    metres = None
                    if latitude is not None:
                        metres = distance_m(value,{"latitude":latitude,"longitude":longitude})
                        if metres > radius_m:
                            continue
                    item = {k:value[k] for k in ("entity_id","catalog_version_id","name","source_category","family",
                        "latitude","longitude","area_key","identity_status","is_enriched","shortlist_rank",
                        "operating_status","source_url","fetched_at")}
                    item["address"] = value["address"] if "address" in value["allowed_fields"] else None
                    item["website_url"] = value["website_url"] if "website" in value["allowed_fields"] else None
                    item["distance_m"] = round(metres,1) if metres is not None else None
                    item["data_level"] = "enriched" if value["is_enriched"] else "basic_source_inventory"
                    item["attribution"] = "Overture Maps Foundation; source-specific licenses in dataset attribution"
                    items.append(item)
                    if len(items) >= limit:
                        break
                if len(values) < 100 and len(items) < limit:
                    return {"items":items,"next_cursor":None}
        return {"items":items,"next_cursor":cursor}

    def coverage(self, city_id):
        with self.engine.connect() as c:
            version = c.execute(select(s.catalog_versions).where(s.catalog_versions.c.geography_id == city_id,
                s.catalog_versions.c.status == "published")).mappings().first()
            if version is None:
                raise DomainError("catalog_not_published",404)
            importer = row(c,s.catalog_import_runs,s.catalog_import_runs.c.catalog_version_id == version["id"])
            sources = c.execute(select(s.source_records,s.source_policies.c.status.label("policy_status"),
                                s.source_policies.c.can_retain_raw,s.source_policies.c.allowed_fields)
                .join(s.source_policies,s.source_policies.c.id == s.source_records.c.policy_id)
                .where(s.source_records.c.id == importer["source_id"])).mappings().one()
            deadline = sources["retention_until"]
            if deadline is not None and deadline.tzinfo is None:
                deadline = deadline.replace(tzinfo=timezone.utc)
            if sources["policy_status"] != "permitted" or not sources["can_retain_raw"] or sources["owner_id"] is not None or sources["publication_status"] != "published" or (deadline is not None and deadline <= utcnow()) or not {"name","coordinates","category"}.issubset(sources["allowed_fields"]):
                raise DomainError("catalog_not_available",404)
            report = dict(importer["report"])
            report["is_complete_city_inventory"] = False
            return {"city_id":city_id,"catalog_version_id":version["id"],"dataset_version":importer["dataset_version"],
                    "scope":{k:importer["manifest"][k] for k in ("bbox","scope_label")},"report":report}

    def publish(self, city_id, version_id, *, expected_active=None, principal=None, key=None):
        if principal is not None and not principal.admin:
            raise DomainError("admin_required",403)
        shape = {"operation":"publish_catalog","city_id":city_id,"version_id":version_id,"expected_active":expected_active}
        with transaction(self.engine) as c:
            if principal is not None:
                cached = receipt(c,principal.owner_id,key,shape)
                if cached is not None:
                    return cached
            row(c,s.geographies,s.geographies.c.id == city_id,lock=True)
            version = row(c,s.catalog_versions,(s.catalog_versions.c.id == version_id) &
                          (s.catalog_versions.c.geography_id == city_id),lock=True)
            active = c.execute(select(s.catalog_versions.c.id).where(s.catalog_versions.c.geography_id == city_id,
                s.catalog_versions.c.status == "published").with_for_update()).scalars().all()
            if len(active)>1 or (active[0] if active else None) != expected_active:
                raise DomainError("catalog_revision_conflict")
            importer = row(c,s.catalog_import_runs,s.catalog_import_runs.c.catalog_version_id == version_id)
            source = row(c,s.source_records,s.source_records.c.id == importer["source_id"],lock=True)
            policy = row(c,s.source_policies,s.source_policies.c.id == source["policy_id"])
            deadline = source["retention_until"]
            if deadline is not None and deadline.tzinfo is None:
                deadline = deadline.replace(tzinfo=timezone.utc)
            required = {"name","coordinates","category","address","website"}
            if source["owner_id"] is not None or source["scope_key"] != "shared" or policy["status"] != "permitted" or not policy["can_retain_raw"] or not required.issubset(policy["allowed_fields"]) or (deadline is not None and deadline <= utcnow()):
                raise DomainError("publication_source_policy_invalid",422)
            snapshots = c.execute(select(s.catalog_snapshots).where(s.catalog_snapshots.c.catalog_version_id == version_id)
                                  .order_by(s.catalog_snapshots.c.entity_id)).mappings().all()
            if len(snapshots) != importer["accepted_records"] or not snapshots:
                raise DomainError("publication_inventory_incomplete",422)
            if any(v["source_id"] != importer["source_id"] for v in snapshots):
                raise DomainError("publication_source_scope_invalid",422)
            c.execute(update(s.catalog_versions).where(s.catalog_versions.c.geography_id == city_id,
                s.catalog_versions.c.status == "published").values(status="retired"))
            c.execute(update(s.catalog_versions).where(s.catalog_versions.c.id == version_id).values(status="published",published_at=utcnow()))
            c.execute(update(s.source_records).where(s.source_records.c.id == source["id"]).values(publication_status="published"))
            still_visible = select(s.catalog_snapshots.c.entity_id).join(s.catalog_versions,
                s.catalog_versions.c.id == s.catalog_snapshots.c.catalog_version_id).where(s.catalog_versions.c.status == "published")
            c.execute(update(s.entities).where(s.entities.c.geography_id == city_id,
                      s.entities.c.id.not_in(still_visible)).values(publication_status="retired"))
            materialize = update(s.entities).where(s.entities.c.id == bindparam("target_id")).values(
                name=bindparam("new_name"),category=bindparam("new_category"),address=bindparam("new_address"),
                latitude=bindparam("new_latitude"),longitude=bindparam("new_longitude"),
                publication_status="published",catalog_version_id=version_id)
            values = [{"target_id":v["entity_id"],"new_name":v["name"],"new_category":v["family"],
                "new_address":v["address"],"new_latitude":v["latitude"],"new_longitude":v["longitude"]} for v in snapshots]
            for batch in batches(values):c.execute(materialize,batch)
            response = {"catalog_version_id":version_id,"status":"published","basic_records":len(snapshots),
                        "shortlisted_records":sum(v["shortlist_rank"] is not None for v in snapshots),
                        "enriched_records":sum(v["is_enriched"] for v in snapshots)}
            return save_receipt(c,principal.owner_id,key,shape,response) if principal is not None else response
