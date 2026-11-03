"""Normalized foundation, ownership constraints and PostgreSQL RLS/PostGIS.

Revision ID: 0001
Revises: None
"""

from alembic import context, op

from trippy.data.schema_v1 import metadata
from trippy.data.rls_v1 import SPATIAL_DDL, statements


revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    connection = op.get_bind()
    metadata.create_all(connection, checkfirst=False)
    if connection.dialect.name == "postgresql":
        op.execute(SPATIAL_DDL)
        for statement in statements():
            op.execute(statement)


def downgrade():
    # An initial-schema downgrade deletes trip data. Never allow it implicitly.
    if context.get_x_argument(as_dictionary=True).get("allow_destructive_downgrade") != "true":
        raise RuntimeError("Downgrade deletes data; restore a verified backup or explicitly opt in on a disposable database")
    metadata.drop_all(op.get_bind(), checkfirst=False)
