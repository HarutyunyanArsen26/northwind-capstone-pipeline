"""Load Northwind CSVs into PostgreSQL's stg schema without changing raw values.

Use from Jupyter (with an existing SQLAlchemy engine):
    from src.stage_raw_data import load_staging
    load_staging(engine, project_root / "data" / "raw")

Or run from PowerShell at the project root:
    python src/stage_raw_data.py
The CLI prompts for your PostgreSQL password; it never saves that password.
"""

from __future__ import annotations

import os
from getpass import getpass
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import Engine, URL

TABLES = (
    "categories", "customers", "employee_territories", "employees",
    "order_details", "orders", "products", "regions", "shippers",
    "suppliers", "territories",
)


def load_staging(engine: Engine, raw_folder: str | Path) -> dict[str, int]:
    """Replace staging rows in one transaction, verifying CSV schema and row counts.

    Rerunning on identical input gives identical staging rows (no appended duplicates).
    Only tables in the stg schema are affected; dw is not modified.
    """
    raw_folder = Path(raw_folder).resolve()
    if not raw_folder.is_dir():
        raise FileNotFoundError(f"Raw CSV directory not found: {raw_folder}")

    available = {p.stem: p for p in raw_folder.glob("*.csv")}
    missing = sorted(set(TABLES) - set(available))
    if missing:
        raise FileNotFoundError(f"Missing CSVs in {raw_folder}: {missing}")

    inspector = inspect(engine)
    existing = set(inspector.get_table_names(schema="stg"))
    missing_tables = sorted(set(TABLES) - existing)
    if missing_tables:
        raise RuntimeError(f"Missing stg tables: {missing_tables}")

    # Do all preflight checks before modifying a database table.
    datasets = {}
    for name in TABLES:
        df = pd.read_csv(available[name], dtype=str, keep_default_na=False)
        expected_columns = [c["name"] for c in inspector.get_columns(name, schema="stg")]
        if list(df.columns) != expected_columns:
            raise ValueError(
                f"Column mismatch in {name}: CSV={list(df.columns)!r}; "
                f"database={expected_columns!r}"
            )
        datasets[name] = df

    counts = {}
    with engine.begin() as conn:
        # PostgreSQL TRUNCATE is transactional: failures roll back the whole load.
        for name in TABLES:
            conn.execute(text(f'TRUNCATE TABLE stg."{name}"'))

        for name, df in datasets.items():
            df.to_sql(
                name=name,
                con=conn,
                schema="stg",
                if_exists="append",
                index=False,
                chunksize=500,
                method="multi",
            )
            count = conn.execute(text(f'SELECT COUNT(*) FROM stg."{name}"')).scalar_one()
            if count != len(df):
                raise RuntimeError(
                    f"Row-count mismatch in {name}: CSV={len(df)} database={count}"
                )
            counts[name] = count
            print(f"{name}: {count} rows loaded")

    print(f"Total rows: {sum(counts.values())}")
    print("Staging load completed successfully!")
    return counts


def main() -> None:
    # The script lives in <project>/src, so this path does not depend on CWD.
    project_root = Path(__file__).resolve().parent.parent
    raw_folder = project_root / "data" / "raw"

    # The terminal password prompt is for direct CLI use, NOT for Jupyter.
    user = os.environ.get("CAPSTONE_DB_USER", "postgres")
    password = os.environ.get("CAPSTONE_DB_PASSWORD")
    if password is None:
        password = getpass(f"PostgreSQL password for {user}: ")

    url = URL.create(
        "postgresql+psycopg2",
        username=user,
        password=password,
        host=os.environ.get("CAPSTONE_DB_HOST", "localhost"),
        port=int(os.environ.get("CAPSTONE_DB_PORT", "5432")),
        database=os.environ.get("CAPSTONE_DB_NAME", "northwind_capstone"),
    )
    engine = create_engine(url)
    try:
        load_staging(engine, raw_folder)
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
