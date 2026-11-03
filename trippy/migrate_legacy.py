"""Private, non-destructive legacy migration preview. Apply is explicitly local."""

import argparse
import hashlib
import json
import os
from pathlib import Path

from sqlalchemy import inspect, text
from sqlalchemy.exc import SQLAlchemyError

from .data.database import make_engine, sqlite_url
from .data.imports import import_trip
from .legacy import normalize_legacy_trip


def write_private(path, content):
    encoded = content if isinstance(content, bytes) else content.encode("utf-8")
    if path.exists():
        if path.read_bytes() != encoded:
            raise ValueError("Migration output already exists with different contents")
        return
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as file:
        file.write(encoded)


def main():
    parser = argparse.ArgumentParser(description="Preview a legacy research/trip/library migration without changing originals")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--owner-id", required=True, help="Verified owner's UUID, or a synthetic UUID for local tests")
    parser.add_argument("--trip-key", help="Stable key required for standalone research")
    parser.add_argument("--output-dir", type=Path, default=Path(".local/legacy-migration"))
    parser.add_argument("--apply-local", action="store_true", help="Import into an already-migrated local SQLite database")
    parser.add_argument("--database", type=Path, default=Path(".local/catalog.sqlite"))
    args = parser.parse_args()
    try:
        raw = args.input.read_bytes()
        payload = json.loads(raw)
        documents = payload if isinstance(payload, list) else [payload]
        bundles = [normalize_legacy_trip(row, owner_id=args.owner_id, trip_key=args.trip_key) for row in documents]
        if len({b.id for b in bundles}) != len(bundles):
            raise ValueError("Library contains duplicate trip IDs")
        output = args.output_dir.resolve()
        output.mkdir(parents=True, mode=0o700, exist_ok=True)
        raw_hash = hashlib.sha256(raw).hexdigest()
        backup = output / f"backup-{raw_hash}.json"
        write_private(backup, raw)
        normalized = json.dumps([b.model_dump(mode="json") for b in bundles], indent=2, ensure_ascii=False, allow_nan=False)
        write_private(output / f"normalized-v1-{raw_hash}.json", normalized)
        statuses = []
        if args.apply_local:
            engine = make_engine(sqlite_url(args.database))
            try:
                with engine.begin() as connection:
                    if "alembic_version" not in inspect(connection).get_table_names() or \
                            connection.execute(text("SELECT version_num FROM alembic_version")).scalar_one_or_none() != "0001":
                        raise ValueError("Run local Alembic migrations before applying a legacy import")
                    for bundle in bundles:
                        statuses.append(import_trip(connection, bundle, backup_ref=str(backup)))
            finally:
                engine.dispose()
        print(json.dumps({"status": "applied_local" if args.apply_local else "preview",
                          "trips": len(bundles), "backup_hash": raw_hash,
                          "results": statuses, "network_calls": 0}, indent=2))
        return 0
    except (ValueError, KeyError, TypeError, AttributeError, OSError, SQLAlchemyError):
        # Never print Pydantic input values, user payloads or connection secrets.
        print(json.dumps({"status": "invalid", "message": "Migration could not complete; check the input, owner UUID, existing outputs and local schema. Originals are unchanged."}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
