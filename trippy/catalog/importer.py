"""Local-first, atomic basic inventory import. No generation or publication."""

from collections import Counter
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path

from sqlalchemy import func, insert, select

from trippy.backend.common import DomainError, fingerprint, row, transaction, utcnow
from trippy.data import schema_v3 as s
from .normalize import flag_duplicates, normalize_feature, shortlist, stable

CITY_ID = stable("geography:wikidata:Q1492")


def digest_file(path):
    digest = sha256()
    with Path(path).open("rb") as stream:
        while data := stream.read(1024*1024):
            digest.update(data)
    return digest.hexdigest()


def load_extract(path):
    path = Path(path)
    if path.stat().st_size > 128_000_000:
        raise ValueError("Source artifact exceeds 128 MB")
    manifest = json.loads(path.with_suffix(path.suffix+".manifest.json").read_text())
    if manifest.get("provider") != "overture" or manifest.get("complete") is not True or manifest.get("sha256") != digest_file(path):
        raise ValueError("Complete, hash-verified Overture extract is required")
    if manifest.get("artifact_bytes") != path.stat().st_size:
        raise ValueError("Artifact byte count differs from manifest")
    bbox = manifest.get("bbox", [])
    if len(bbox) != 4 or not (-180 <= bbox[0] < bbox[2] <= 180 and -90 <= bbox[1] < bbox[3] <= 90) or (bbox[2]-bbox[0])*(bbox[3]-bbox[1]) > .1:
        raise ValueError("A small explicit geographic scope is required")
    parsed = datetime.fromisoformat(manifest["retrieved_at"])
    if parsed.utcoffset() is None or parsed > utcnow():
        raise ValueError("Source retrieval time must be real, timezone-aware and nonfuture")
    records, seen, rejections = [], {}, Counter()
    count, duplicates = 0, 0
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            count += 1
            if count > 100000 or len(line.encode()) > 64000:
                raise ValueError("Source record/line ceiling exceeded")
            try:
                feature = json.loads(line)
                record = normalize_feature(feature, bbox)
            except (ValueError, TypeError, AttributeError) as error:
                code = str(error) if isinstance(error, ValueError) and len(str(error)) < 60 else "invalid_record_shape"
                rejections[code] += 1
                continue
            signature = fingerprint(record)
            if record["external_id"] in seen:
                if seen[record["external_id"]] != signature:
                    raise ValueError("Conflicting records share a source ID; import requires review")
                duplicates += 1
                continue
            seen[record["external_id"]] = signature
            records.append(record)
    if count != manifest.get("records"):
        raise ValueError("Record count differs from manifest")
    conflicts, capped = flag_duplicates(records)
    report = {"input_records": count, "accepted_records": len(records), "rejected_records": sum(rejections.values()),
        "duplicate_records": duplicates, "rejections": dict(rejections), "by_family": dict(Counter(v["family"] for v in records)),
        "by_area": dict(Counter(v["area_key"] for v in records)), "identity_conflicts": len(conflicts),
        "identity_conflict_report_capped": capped, "shortlist": shortlist(records), "enriched_records": 0,
        "with_address": sum(bool(v["address"]) for v in records), "with_website": sum(bool(v["website_url"]) for v in records),
        "operating_status_counts": dict(Counter(v["operating_status"] or "unknown" for v in records)),
        "source_datasets": dict(Counter(dataset for v in records for dataset in
            {source["dataset"] for source in v["source_properties"]["sources"]}))}
    if not records:
        raise ValueError("No validated source records; empty catalog will not be created")
    return manifest, records, conflicts, report


def put_if_missing(c, table, values):
    found = c.execute(select(table.c.id).where(table.c.id == values["id"])).first()
    if found is None:
        c.execute(insert(table).values(**values))


def policy(c, provider, version, url, allowed_fields):
    policy_id = stable(f"policy:{provider}:{version}")
    put_if_missing(c, s.source_policies, {"id":policy_id,"provider":provider,"policy_version":version,
        "agreement_url":url,"status":"permitted","allowed_fields":allowed_fields,
        "can_retain_raw":True,"can_use_in_prompt":True,"reviewed_at":utcnow()})
    existing = row(c,s.source_policies,s.source_policies.c.id == policy_id)
    if existing["status"] != "permitted" or not existing["can_retain_raw"] or not set(allowed_fields).issubset(existing["allowed_fields"]):
        raise DomainError("source_policy_not_permitted")
    return policy_id


def seed_geography(c, document, *, retrieved_at):
    """Wikidata supplies names/coordinates; hierarchy is explicit app scope."""
    if retrieved_at.utcoffset() is None or retrieved_at > utcnow():
        raise ValueError("Geography fetch time must be real and timezone-aware")
    policy_id = policy(c,"wikidata","cc0-geography-v1","https://www.wikidata.org/wiki/Wikidata:Licensing",["name","coordinates","external_id"])
    definitions = [("Q46","continent",None), ("Q29","country","Q46"), ("Q5705","region","Q29"), ("Q1492","city","Q5705")]
    for qid, kind, parent in definitions:
        source = document.get("entities",{}).get(qid,{})
        name = source.get("labels",{}).get("en",{}).get("value")
        coordinates = [v.get("mainsnak",{}).get("datavalue",{}).get("value",{}) for v in source.get("claims",{}).get("P625",[])
                       if v.get("rank") != "deprecated"]
        point = next((v for v in coordinates if v.get("globe") == "http://www.wikidata.org/entity/Q2"), None)
        if not name or not point:
            raise ValueError("Required geography source identity/coordinate is absent")
        geography_id = stable("geography:wikidata:"+qid)
        source_id = stable("source:wikidata:"+qid+":"+str(source.get("lastrevid","unknown")))
        put_if_missing(c,s.source_records,{"id":source_id,"scope_key":"shared","policy_id":policy_id,
            "url":"https://www.wikidata.org/wiki/"+qid,"publisher":"Wikidata","source_type":"structured_dataset",
            "fetched_at":retrieved_at,"publication_status":"published"})
        put_if_missing(c,s.geographies,{"id":geography_id,"kind":kind,"name":name,
            "parent_id":stable("geography:wikidata:"+parent) if parent else None,
            "country_code":"ES" if kind in {"country","region","city"} else None,
            "timezone":"Europe/Madrid" if kind in {"region","city"} else None,
            "latitude":point["latitude"],"longitude":point["longitude"]})
        put_if_missing(c,s.geography_references,{"id":stable("geography-ref:"+qid),"geography_id":geography_id,
            "source_id":source_id,"provider":"wikidata","external_id":qid})


def batches(values, size=500):
    for offset in range(0,len(values),size):
        yield values[offset:offset+size]


def database_bytes(c):
    if c.dialect.name == "sqlite":
        return c.exec_driver_sql("PRAGMA page_count").scalar_one()*c.exec_driver_sql("PRAGMA page_size").scalar_one()
    raise ValueError("Connected inventory import has not been enabled")


def import_extract(engine, path, geography_document, *, geography_retrieved_at, max_database_bytes=256_000_000):
    if engine.dialect.name != "sqlite":
        raise ValueError("Stage-3 importer is local-only until connected verification")
    manifest, records, conflicts, report = load_extract(path)
    scope_hash = fingerprint({"bbox":manifest["bbox"],"scope_label":manifest["scope_label"]})
    import_id = stable("import:overture:"+manifest["release"]+":"+manifest["sha256"]+":"+scope_hash)
    with transaction(engine) as c:
        found = c.execute(select(s.catalog_import_runs).where(s.catalog_import_runs.c.id == import_id)).mappings().first()
        if found:
            return {"import_id":import_id,"catalog_version_id":found["catalog_version_id"],"already_imported":True,"report":found["report"]}
        seed_geography(c,geography_document,retrieved_at=geography_retrieved_at)
        row(c,s.geographies,s.geographies.c.id == CITY_ID,lock=True)
        next_version = c.execute(select(func.coalesce(func.max(s.catalog_versions.c.version),0)).where(
                                s.catalog_versions.c.geography_id == CITY_ID)).scalar_one()+1
        version_id = stable("catalog-version:"+import_id)
        c.execute(insert(s.catalog_versions).values(id=version_id,geography_id=CITY_ID,version=next_version))
        policy_id = policy(c,"overture-places","permissive-2026-10-v1","https://docs.overturemaps.org/attribution/",
            ["name","coordinates","category","address","website","source_ids","source_version","confidence","operating_status"])
        source_id = stable("source:overture:"+manifest["release"]+":"+manifest["sha256"])
        put_if_missing(c,s.source_records,{"id":source_id,"scope_key":"shared","policy_id":policy_id,
            "url":manifest["collection_url"],"publisher":"Overture Maps Foundation","source_type":"regional_geoparquet",
            "fetched_at":datetime.fromisoformat(manifest["retrieved_at"]).astimezone(timezone.utc),"publication_status":"draft"})
        existing = dict(c.execute(select(s.provider_entities.c.external_id,s.provider_entities.c.entity_id)
                                 .where(s.provider_entities.c.provider == "overture")).all())
        new_entities, mappings = [], []
        for record in records:
            if record["external_id"] in existing:
                if existing[record["external_id"]] != record["entity_id"]:
                    raise DomainError("existing_identity_mapping_requires_review")
            else:
                new_entities.append({"id":record["entity_id"],"kind":"place","name":record["name"],
                    "category":record["family"],"geography_id":CITY_ID,"latitude":record["latitude"],"longitude":record["longitude"],
                    "address":record["address"],"timezone":"Europe/Madrid","catalog_version_id":version_id})
                mappings.append({"id":stable("provider:overture:"+record["external_id"]),"provider":"overture",
                    "external_id":record["external_id"],"entity_id":record["entity_id"],"policy_id":policy_id,
                    "match_status":"confirmed","dataset_version":manifest["release"]})
        for batch in batches(new_entities):c.execute(insert(s.entities),batch)
        for batch in batches(mappings):c.execute(insert(s.provider_entities),batch)
        snapshots = [{**v,"catalog_version_id":version_id,"source_id":source_id} for v in records]
        for batch in batches(snapshots):c.execute(insert(s.catalog_snapshots),batch)
        for batch in batches([{**v,"id":stable("conflict:"+version_id+":"+v["first_entity_id"]+":"+v["second_entity_id"]),
                              "catalog_version_id":version_id} for v in conflicts]):
            c.execute(insert(s.catalog_identity_conflicts),batch)
        size = database_bytes(c)
        if size > max_database_bytes:
            raise DomainError("local_database_size_cap_exceeded",422)
        report["database_bytes_before_import_receipt"] = size
        c.execute(insert(s.catalog_import_runs).values(id=import_id,geography_id=CITY_ID,catalog_version_id=version_id,
            source_id=source_id,provider="overture",dataset_version=manifest["release"],input_sha256=manifest["sha256"],
            scope_sha256=scope_hash,input_records=report["input_records"],accepted_records=report["accepted_records"],
            rejected_records=report["rejected_records"],duplicate_records=report["duplicate_records"],manifest=manifest,report=report))
        if database_bytes(c) > max_database_bytes:
            raise DomainError("local_database_size_cap_exceeded",422)
        return {"import_id":import_id,"catalog_version_id":version_id,"already_imported":False,"report":report}
