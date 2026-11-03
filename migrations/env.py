"""Alembic defaults to a local DB. Remote targets require explicit connected=true."""

from pathlib import Path

from alembic import context

from trippy.data.database import make_engine
from trippy.data.schema import metadata
from trippy_config import read_environment


config = context.config
options = context.get_x_argument(as_dictionary=True)
url = config.get_main_option("sqlalchemy.url")
if options.get("connected") == "true":
    values = read_environment(Path(__file__).resolve().parents[1] / ".env")
    url = values.get("MIGRATION_DATABASE_URL")
    if not url:
        raise ValueError("MIGRATION_DATABASE_URL is required for a connected migration")
elif not url.startswith("sqlite:") and not context.is_offline_mode():
    raise ValueError("Remote migration requires the explicit -x connected=true option")

if context.is_offline_mode():
    # PostgreSQL SQL can be rendered without any connection/credential.
    dialect_name = options.get("dialect", "sqlite")
    if dialect_name not in {"sqlite", "postgresql"}:
        raise ValueError("Unsupported SQL preview dialect")
    context.configure(dialect_name=dialect_name, target_metadata=metadata,
                      literal_binds=True, dialect_opts={"paramstyle": "named"})
    with context.begin_transaction():
        context.run_migrations()
else:
    if url.startswith("sqlite:"):
        (Path(__file__).resolve().parents[1] / ".local").mkdir(exist_ok=True)
    engine = make_engine(url)
    try:
        with engine.connect() as connection:
            def include_object(obj, name, object_type, reflected, compare_to):
                # These PostgreSQL expression indexes live in the frozen
                # spatial migration, not cross-dialect SQLAlchemy metadata.
                managed_spatial_indexes = {"ix_entities_location_gist", "ix_user_places_location_gist", "ix_entities_name_fts"}
                return not (object_type == "index" and reflected and compare_to is None and name in managed_spatial_indexes)

            context.configure(connection=connection, target_metadata=metadata, compare_type=True,
                              include_object=include_object,
                              render_as_batch=connection.dialect.name == "sqlite")
            with context.begin_transaction():
                context.run_migrations()
    finally:
        engine.dispose()
