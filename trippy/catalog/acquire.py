"""Bounded STAC discovery and regional Overture GeoParquet extraction."""

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import struct
from urllib.parse import urlparse
from urllib.request import Request, urlopen

STAC = "https://stac.overturemaps.org"
BARCELONA_BBOX = (2.05, 41.30, 2.24, 41.47)
TRAVEL_CATEGORIES = r"(^|_)(restaurant|restaurants|cafe|coffee|bakery|bakeries|brunch|bar|pub|nightclub|museum|monument|landmark|attraction|gallery|park|beach|garden|trail|viewpoint|hotel|hostel|lodging|market|store|shop|shopping|station|airport|theatre|theater|cathedral|church|basilica|castle|palace|aquarium|zoo)(_|$)"


def overlaps(first, second):
    return first[0] <= second[2] and first[2] >= second[0] and first[1] <= second[3] and first[3] >= second[1]


def get_json(url, *, allowed_hosts=("stac.overturemaps.org", "www.wikidata.org")):
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in allowed_hosts or parsed.username or parsed.password:
        raise ValueError("Untrusted source endpoint")
    request = Request(url, headers={"User-Agent": "TrippyCatalogPilot/0.1 (bounded open-data research)", "Accept": "application/json"})
    with urlopen(request, timeout=30) as response:
        if urlparse(response.url).hostname not in allowed_hosts:
            raise ValueError("Unexpected source redirect")
        raw = response.read(2_000_001)
        if len(raw) > 2_000_000:
            raise ValueError("Source metadata exceeds the bounded response size")
    return json.loads(raw)


def discover(release=None, bbox=BARCELONA_BBOX):
    root = get_json(STAC + "/catalog.json")
    release = release or root["latest"]
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}\.\d+", release):
        raise ValueError("Invalid pinned Overture release")
    if release not in {link.get("title", "").split()[0] for link in root["links"] if link.get("rel") == "child"}:
        raise ValueError("Release is not in the source catalog")
    collection_url = f"{STAC}/{release}/places/place/collection.json"
    collection = get_json(collection_url)
    links = [v["href"] for v in collection["links"] if v["rel"] == "item"]
    if not links or len(links) > 100:
        raise ValueError("Unsupported STAC collection size")
    with ThreadPoolExecutor(max_workers=4) as pool:
        items = list(pool.map(get_json, links))
    selected = []
    for item in items:
        if overlaps(item["bbox"], bbox):
            asset = item["assets"]["aws"]
            parsed = urlparse(asset["href"])
            if parsed.scheme != "https" or parsed.hostname != "overturemaps-us-west-2.s3.us-west-2.amazonaws.com" or "/theme=places/type=place/" not in parsed.path:
                raise ValueError("Unexpected regional Places asset")
            if item["properties"].get("storage:schemes", {}).get("aws", {}).get("requester_pays") is not False:
                raise ValueError("Only public, non-requester-pays source assets are allowed")
            selected.append({"url": asset["href"], "item_id": item["id"], "bbox": item["bbox"],
                             "remote_file_bytes": asset.get("file:size")})
    if not selected or len(selected) > 4:
        raise ValueError("Regional pilot must intersect between one and four source assets")
    return {"provider": "overture", "release": release, "collection_url": collection_url,
            "bbox": list(bbox), "scope_label": "Barcelona urban pilot bounding box (not a municipal polygon)",
            "assets": selected, "retrieved_at": datetime.now(timezone.utc).isoformat()}


def point_wkb(value):
    """Decode two-dimensional WKB Point; never infer a location from bbox."""
    if not isinstance(value, (bytes, bytearray, memoryview)) or len(value) != 21 or value[0] not in (0, 1):
        raise ValueError("Expected a two-dimensional WKB Point")
    endian = "<" if value[0] == 1 else ">"
    kind, x, y = struct.unpack(endian + "Idd", bytes(value)[1:])
    if kind != 1:
        raise ValueError("Source geometry must be a Point")
    return x, y


def extract(output, *, release=None, bbox=BARCELONA_BBOX, max_records=100000, max_bytes=128_000_000, workspace=None, inspect_only=False):
    """Explicit network operation. Output and manifest never overwrite files."""
    import duckdb

    output = Path(output).resolve()
    manifest_path = output.with_suffix(output.suffix + ".manifest.json")
    if output.exists() or manifest_path.exists():
        raise FileExistsError("Source extract exists; reuse it or choose a new path")
    if not 1 <= max_records <= 100000:
        raise ValueError("A bounded record ceiling is required")
    if not 1 <= max_bytes <= 128_000_000:
        raise ValueError("Extract byte ceiling must be at most 128 MB")
    workspace = Path(workspace or output.parent / "duckdb").resolve()
    workspace.mkdir(parents=True, exist_ok=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    manifest = discover(release, bbox)
    print(json.dumps({"phase": "regional_extract", "release": manifest["release"],
                      "selected_assets": len(manifest["assets"]), "record_ceiling": max_records}), flush=True)
    connection = duckdb.connect(config={"memory_limit": "512MB", "threads": 2,
        "extension_directory": str(workspace / "extensions"), "temp_directory": str(workspace / "temp")})
    try:
        connection.execute("INSTALL httpfs FROM 'https://extensions.duckdb.org'")
        connection.execute("LOAD httpfs")
        connection.execute("SET http_timeout=30")
        connection.execute("SET http_retries=2")
        # No spatial extension is needed: preserve and decode source WKB.
        paths = [a["url"] for a in manifest["assets"]]
        descriptions = connection.execute("DESCRIBE SELECT * FROM read_parquet(?)", [paths]).fetchall()
        columns = {v[0] for v in descriptions}
        required = {"id", "names", "geometry", "bbox", "sources"}
        if not required.issubset(columns) or not ({"taxonomy", "categories"} & columns):
            raise ValueError("Unsupported Places schema; do not silently reinterpret columns")
        fields = [v for v in ("id", "version", "names", "taxonomy", "categories", "basic_category", "sources",
                  "addresses", "websites", "confidence", "operating_status", "geometry") if v in columns]
        if inspect_only:
            counts = connection.execute("SELECT addresses[1].locality, count(*) FROM read_parquet(?) WHERE "
                "bbox.xmin BETWEEN ? AND ? AND bbox.ymin BETWEEN ? AND ? GROUP BY 1 ORDER BY 2 DESC LIMIT 15",
                [paths, bbox[0], bbox[2], bbox[1], bbox[3]]).fetchall()
            print(json.dumps({"phase":"locality_counts","counts":counts}),flush=True)
            return {"records":0,"artifact_bytes":0}
        category_column = "taxonomy" if "taxonomy" in columns else "categories"
        source_filter = "bbox.xmin BETWEEN ? AND ? AND bbox.ymin BETWEEN ? AND ? " + \
            "AND lower(addresses[1].locality) = 'barcelona' AND regexp_matches(" + category_column + ".primary, ?)"
        parameters = [paths, bbox[0], bbox[2], bbox[1], bbox[3], TRAVEL_CATEGORIES]
        total = connection.execute("SELECT count(*) FROM read_parquet(?) WHERE " + source_filter,parameters).fetchone()[0]
        print(json.dumps({"phase": "source_count", "records": total}), flush=True)
        if total > max_records:
            raise ValueError(f"Regional source has {total} records, above the {max_records} ceiling")
        # Only verified column names are interpolated; path/filter values bind.
        query = "SELECT " + ",".join('"' + v + '"' for v in fields) + " FROM read_parquet(?) WHERE " + source_filter + " LIMIT ?"
        cursor = connection.execute(query, [*parameters,max_records + 1])
        count, bytes_written = 0, 0
        import os
        fd = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            while batch := cursor.fetchmany(500):
                for values in batch:
                    count += 1
                    if count > max_records:
                        raise ValueError("Extract exceeds record ceiling; partial artifact is not importable")
                    feature = dict(zip(fields, values))
                    x, y = point_wkb(feature.pop("geometry"))
                    # Retain a declared basic-field projection, not the full
                    # source payload. Field paths/IDs/license/check time remain.
                    feature["sources"] = [{k: v for k, v in source.items() if v is not None and k in
                        {"property", "dataset", "license", "record_id", "update_time"}}
                        for source in feature.get("sources") or []]
                    feature["addresses"] = (feature.get("addresses") or [])[:1]
                    feature["websites"] = (feature.get("websites") or [])[:2]
                    record = {"type": "Feature", "geometry": {"type": "Point", "coordinates": [x, y]}, "properties": feature}
                    line = json.dumps(record, ensure_ascii=False, allow_nan=False, default=lambda v: v.isoformat()) + "\n"
                    bytes_written += len(line.encode("utf-8"))
                    if bytes_written > max_bytes:
                        raise ValueError("Extract exceeds output byte ceiling; partial artifact is not importable")
                    stream.write(line)
                if count % 5000 == 0:
                    print(json.dumps({"phase": "writing", "records": count}), flush=True)
        from hashlib import sha256
        manifest.update({"records": count, "artifact_bytes": bytes_written,
                         "sha256": sha256(output.read_bytes()).hexdigest(), "complete": True,
                         "duckdb_version": duckdb.__version__, "schema_columns": sorted(columns)})
        manifest["projection"] = "Basic Places fields; first address, first two websites; sources: property/dataset/license/record_id/update_time"
        manifest["scope_label"] = "Source locality Barcelona within pilot bbox; travel/practical source-category filter (not a municipal polygon)"
        manifest["source_filters"] = {"locality":"Barcelona","primary_category_regex":TRAVEL_CATEGORIES}
        with manifest_path.open("x", encoding="utf-8") as stream:
            json.dump(manifest, stream, ensure_ascii=False, indent=2)
        return manifest
    finally:
        connection.close()


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Download a bounded Barcelona Places extract; no model calls")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--release")
    parser.add_argument("--inspect", action="store_true")
    args = parser.parse_args()
    result = extract(args.output, release=args.release, inspect_only=args.inspect)
    print(json.dumps({"phase": "complete", "records": result["records"], "artifact_bytes": result["artifact_bytes"]}))
