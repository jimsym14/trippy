"""Explicit SQLite/fake-provider tools; never connects to Azure or Supabase."""

import argparse
from datetime import timedelta
from decimal import Decimal
import json
from pathlib import Path
import time
from uuid import UUID, uuid4

from alembic import command
from alembic.config import Config

from trippy.data.database import make_engine, sqlite_url
from .auth import Principal
from .budgets import Budgets
from .common import transaction, utcnow
from .contracts import NewJob
from .queue import Queue
from .repository import Repository
from .worker import Worker


def main(argv=None):
    parser = argparse.ArgumentParser(description="Trippy local-only Stage-2 tools")
    parser.add_argument("operation", choices=("preview", "worker"))
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--once", action="store_true", help="Worker: process at most one queued job")
    args = parser.parse_args(argv)
    path = args.database.resolve()
    if args.operation == "preview":
        if path.exists():
            parser.error("Preview requires a new disposable database path; existing data is preserved")
        path.parent.mkdir(parents=True, exist_ok=True)
        # Create the file exclusively/private before migrations open it.
        import os
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
        config = Config(str(Path(__file__).resolve().parents[2] / "alembic.ini"))
        config.set_main_option("sqlalchemy.url", sqlite_url(path))
        command.upgrade(config, "head")
    elif not path.is_file():
        parser.error("Worker requires an existing, migrated local database")
    engine = make_engine(sqlite_url(path))
    queue = Queue(engine)
    try:
        if args.operation == "preview":
            owner = str(uuid4())
            trip = Repository(engine).create_trip(owner, "synthetic-trip", {"destination": "Barcelona (synthetic preview)"})
            now = utcnow()
            with transaction(engine) as c:
                for scope in ("global", "owner:" + owner):
                    Budgets(engine).configure(c, scope_key=scope, provider="fake", currency="USD",
                        period_start=now, period_end=now+timedelta(days=1), cap_amount=Decimal("0"))
            job = queue.enqueue(Principal(str(UUID(owner))), "synthetic-job",
                NewJob(task_type="trip_research", trip_id=trip["id"], expected_trip_revision=0).model_dump(mode="json"))
            result = Worker(queue).run_once()
            events = queue.events(owner, job["job_id"], 0, 100)
            print(json.dumps({"worker": result, "event_sequences": [e["sequence"] for e in events],
                              "provider": "fake", "paid_calls": 0}, ensure_ascii=False))
        else:
            worker = Worker(queue)
            while True:
                result = worker.run_once()
                print(json.dumps(result), flush=True)
                if args.once:
                    break
                time.sleep(3)
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
