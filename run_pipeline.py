"""Run the complete Northwind CSV -> stg -> dw pipeline.

Jupyter (use the engine you already verified):
    import sys
    sys.path.insert(0, str(orders_path.parents[2]))
    from run_pipeline import run_pipeline
    run_pipeline(engine)

PowerShell (run from the project root):
    python run_pipeline.py
    # Enter PostgreSQL password in the terminal when prompted.

The run is repeatable. No password is written to this repository.
"""

from __future__ import annotations

import os
from getpass import getpass
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.engine import Engine

from src.config import PROJECT_ROOT, RAW_DIR, SQL_DIR, get_database_settings
from src.db_connector import create_db_engine, create_db_if_missing
from src.stage_raw_data import TABLES, load_staging
from src.extract_raw_data import ensure_source_csvs
from src.transform_warehouse import create_staging_tables, load_warehouse


def check_project_files(root: Path) -> None:
    missing = [str(root / "sql" / x) for x in (
        "02_create_staging.sql", "03_create_warehouse.sql",
        "04_upsert_dimensions.sql", "05_upsert_fact_sales.sql",
    ) if not (root / "sql" / x).is_file()]
    if missing:
        raise FileNotFoundError("Required files are missing:\n" + "\n".join(missing))


def validate_pipeline(engine: Engine) -> None:
    """Reconcile dimensions, order lines, financial totals and calendar bounds."""
    with engine.connect() as conn:
        expected = {
            "dim_customer": conn.execute(text("SELECT COUNT(*) FROM stg.customers")).scalar_one(),
            "dim_product": conn.execute(text("SELECT COUNT(*) FROM stg.products")).scalar_one(),
            "dim_employee": conn.execute(text("SELECT COUNT(*) FROM stg.employees")).scalar_one(),
            "dim_shipper": conn.execute(text("SELECT COUNT(*) FROM stg.shippers")).scalar_one(),
            "fact_sales": conn.execute(text("SELECT COUNT(*) FROM stg.order_details")).scalar_one(),
        }
        for table_name, source_rows in expected.items():
            actual_rows = conn.execute(text(f"SELECT COUNT(*) FROM dw.{table_name}")).scalar_one()
            if actual_rows != source_rows:
                raise AssertionError(f"{table_name}: DW {actual_rows}, source {source_rows}")
            print(f"Verified dw.{table_name}: {actual_rows} rows")

        date_info = conn.execute(text("""
            SELECT COUNT(*), MIN(full_date), MAX(full_date) FROM dw.dim_date
        """)).one()
        if (date_info[0], str(date_info[1]), str(date_info[2])) != (
            2925592, "1990-01-01", "9999-12-31"
        ):
            raise AssertionError(f"Unexpected date dimension: {date_info!r}")
        print(f"Verified dw.dim_date: {date_info[0]} dates")

        totals = conn.execute(text("""
            SELECT COUNT(*), COUNT(DISTINCT (order_id, product_sk)),
                   COUNT(DISTINCT order_id), SUM(gross_sales),
                   SUM(discount_amount), SUM(net_sales)
            FROM dw.fact_sales
        """)).one()
        if totals[0] != totals[1]:
            raise AssertionError("Duplicate order/product pairs in fact_sales")
        print("Fact: lines={}, unique order/product={}, orders={}, gross={}, discount={}, net={}".format(*totals))

        missing_fk = conn.execute(text("""
            SELECT COUNT(*) FROM dw.fact_sales f
            LEFT JOIN dw.dim_customer c ON c.customer_sk = f.customer_sk
            LEFT JOIN dw.dim_product p ON p.product_sk = f.product_sk
            LEFT JOIN dw.dim_date d ON d.date_sk = f.order_date_sk
            WHERE c.customer_sk IS NULL OR p.product_sk IS NULL OR d.date_sk IS NULL
        """)).scalar_one()
        if missing_fk:
            raise AssertionError(f"Unmatched fact foreign keys: {missing_fk}")
        print("Fact foreign keys: PASS")


def run_pipeline(
    engine: Engine, project_root: Path = PROJECT_ROOT,
    refresh_source: bool = False, expected_db: str = "northwind_capstone"
) -> None:
    """Get 11 CSVs, build staging, UPSERT warehouse and validate."""
    project_root = Path(project_root).resolve()
    raw_dir, sql_dir = project_root / "data" / "raw", project_root / "sql"
    check_project_files(project_root)
    print("Step 0/4: Confirming source CSVs")
    ensure_source_csvs(raw_dir, refresh=refresh_source)
    with engine.connect() as conn:
        current_database = conn.execute(text("SELECT current_database() ")).scalar_one()
    if current_database != expected_db:
        raise ValueError(f"Wrong active database: {current_database!r}; expected {expected_db}")
    print("Step 1/4: Creating/confirming staging tables")
    create_staging_tables(engine, sql_dir)
    print("Step 2/4: Loading 11 CSVs into stg")
    load_staging(engine, raw_dir)
    print("Step 3/4: Creating/updating the dw Star Schema")
    load_warehouse(engine, sql_dir)
    print("Step 4/4: Validating loaded tables")
    validate_pipeline(engine)
    print("Pipeline completed successfully!")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Northwind capstone ETL")
    parser.add_argument(
        "--refresh-source", action="store_true",
        help="Re-download the 11 CSVs from GitHub, overwriting local raw copies"
    )
    args = parser.parse_args()
    settings = get_database_settings()
    password = os.environ.get("CAPSTONE_DB_PASSWORD")
    if password is None:
        password = getpass(f"PostgreSQL password for {settings.username}: ")
    # For direct PowerShell use, create target database if missing.
    create_db_if_missing(settings, password)
    engine = create_db_engine(settings, password)
    try:
        run_pipeline(engine, refresh_source=args.refresh_source, expected_db=settings.name)
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
