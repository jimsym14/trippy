"""Explicit local API factory; no schema creation, paid provider or deployment."""

from pathlib import Path
from decimal import Decimal

from trippy_config import read_environment
from trippy.data.database import make_engine, sqlite_url
from .api import create_app
from .auth import SupabaseJWTVerifier


def app():
    root = Path(__file__).resolve().parents[2]
    values = read_environment(root / ".env")
    # A remote DB requires explicit runtime opt-in independently of migrations.
    connected = values.get("TRIPPY_BACKEND_CONNECTED", "false") == "true"
    url = values.get("DATABASE_URL") if connected else sqlite_url(root / ".local/catalog.sqlite")
    if connected and not url:
        raise ValueError("Connected backend requires DATABASE_URL")
    engine = make_engine(url, pool_size=int(values.get("TRIPPY_DB_POOL_SIZE", "3")))
    verifier = SupabaseJWTVerifier(values["SUPABASE_URL"]) if values.get("SUPABASE_URL") else None
    return create_app(engine, auth=verifier, provider="fake", job_cap=Decimal("0"))
