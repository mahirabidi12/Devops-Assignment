"""create patients table

Revision ID: 0001
Revises:
Create Date: 2026-10-16
"""
import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "patients",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("age", sa.Integer(), nullable=False),
        sa.Column("phone", sa.String(length=20), nullable=False),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="waiting"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    # Indexes on the columns the API filters and sorts by. Without these the
    # list endpoint degrades to a full scan as the table grows.
    op.create_index("ix_patients_name", "patients", ["name"])
    op.create_index("ix_patients_status", "patients", ["status"])


def downgrade() -> None:
    op.drop_index("ix_patients_status", table_name="patients")
    op.drop_index("ix_patients_name", table_name="patients")
    op.drop_table("patients")
