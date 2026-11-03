"""Regional inventory snapshots, provenance and publication. Revision 0003."""

from alembic import context, op
from trippy.data.schema_v3 import metadata

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None
TABLES = ("geography_references", "catalog_import_runs", "catalog_snapshots", "catalog_identity_conflicts")


def upgrade():
    c = op.get_bind()
    for name in TABLES:
        metadata.tables[name].create(c, checkfirst=False)
        if c.dialect.name == "postgresql":
            op.execute(f'ALTER TABLE "{name}" ENABLE ROW LEVEL SECURITY')
            op.execute(f'ALTER TABLE "{name}" FORCE ROW LEVEL SECURITY')
            op.execute(f'REVOKE ALL ON "{name}" FROM anon, authenticated')
            op.execute(f'GRANT ALL ON "{name}" TO service_role')
    # Snapshot/import metadata is served through the version/policy-aware API.
    # No direct write or raw-source payload grants to authenticated clients.


def downgrade():
    if context.get_x_argument(as_dictionary=True).get("allow_destructive_downgrade") != "true":
        raise RuntimeError("Downgrade deletes data (catalog inventory); restore a backup or explicitly opt in")
    for name in reversed(TABLES):
        metadata.tables[name].drop(op.get_bind(), checkfirst=False)
