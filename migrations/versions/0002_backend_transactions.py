"""Durable receipts/results and atomic multi-scope budgets. Revision 0002."""

from alembic import context, op
from trippy.data.schema_v2 import metadata

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None
TABLES = ("budget_accounts", "reservation_allocations", "mutation_receipts", "job_results")


def upgrade():
    connection = op.get_bind()
    for name in TABLES:
        metadata.tables[name].create(connection, checkfirst=False)
        if connection.dialect.name == "postgresql":
            op.execute(f'ALTER TABLE "{name}" ENABLE ROW LEVEL SECURITY')
            op.execute(f'ALTER TABLE "{name}" FORCE ROW LEVEL SECURITY')
            op.execute(f'REVOKE ALL ON "{name}" FROM anon, authenticated')
            op.execute(f'GRANT ALL ON "{name}" TO service_role')
    # Internal budget/receipt tables are deliberately backend-only. Job results
    # use the owner-checked API, avoiding a second mutation or payload bypass.


def downgrade():
    if context.get_x_argument(as_dictionary=True).get("allow_destructive_downgrade") != "true":
        raise RuntimeError("Downgrade deletes data (job/budget state); restore a backup or opt in on a disposable DB")
    for name in reversed(TABLES):
        metadata.tables[name].drop(op.get_bind(), checkfirst=False)
