"""Execute the saved PostgreSQL DDL and UPSERT scripts in order."""

from __future__ import annotations

from pathlib import Path
from sqlalchemy.engine import Engine

# 01_create_db_and_schemas.sql contains CREATE DATABASE: the CLI bootstrap
# handles it safely before connecting. Subsequent SQL runs on the target DB.
WAREHOUSE_SQL = (
    "03_create_warehouse.sql",
    "04_upsert_dimensions.sql",
    "05_upsert_fact_sales.sql",
)


def execute_sql_file(engine: Engine, file_path: Path) -> None:
    """Execute a complete SQL file using psycopg2's multiple-statement support.

    The ACA SQL files contain BEGIN/COMMIT around multi-statement transformations.
    psycopg2 accepts them as one script with no bound params. Autocommit here
    lets each SQL file explicitly manage its own transaction boundaries.
    """
    sql_text = file_path.read_text(encoding="utf-8-sig")
    if not sql_text.strip():
        raise ValueError(f"SQL file is empty: {file_path}")
    conn = engine.raw_connection()
    try:
        conn.autocommit = True
        with conn.cursor() as cursor:
            cursor.execute(sql_text)
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    print(f"Executed {file_path.name}")


def create_staging_tables(engine: Engine, sql_dir: Path) -> None:
    execute_sql_file(engine, sql_dir / "02_create_staging.sql")


def load_warehouse(engine: Engine, sql_dir: Path) -> None:
    for filename in WAREHOUSE_SQL:
        execute_sql_file(engine, sql_dir / filename)
