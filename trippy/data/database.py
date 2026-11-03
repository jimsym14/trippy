"""Explicit connection factories; no automatic schema creation or migration."""

from pathlib import Path

from sqlalchemy import create_engine, event
from sqlalchemy.engine import make_url


def make_engine(url, *, pool_size=3):
    try:
        parsed = make_url(url)
    except Exception:
        raise ValueError("Invalid database connection settings") from None
    if not 1 <= pool_size <= 20:
        raise ValueError("Database pool size must be between 1 and 20")
    if parsed.get_backend_name() == "sqlite":
        engine = create_engine(parsed, echo=False, hide_parameters=True)

        @event.listens_for(engine, "connect")
        def enable_foreign_keys(connection, _record):
            connection.execute("PRAGMA foreign_keys=ON")

        return engine
    if parsed.get_backend_name() != "postgresql":
        raise ValueError("Only PostgreSQL or local SQLite are supported")
    parsed = parsed.set(drivername="postgresql+psycopg")
    return create_engine(parsed, pool_size=pool_size, max_overflow=0,
                         pool_pre_ping=True, echo=False, hide_parameters=True,
                         connect_args={"connect_timeout": 10})


def sqlite_url(path):
    return "sqlite:///" + str(Path(path).resolve())
