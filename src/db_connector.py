"""PostgreSQL connection, using one password supplied at runtime."""

from __future__ import annotations

import psycopg2
from psycopg2 import sql
from sqlalchemy import create_engine
from sqlalchemy.engine import Engine, URL

from .config import DatabaseSettings


def create_db_if_missing(settings: DatabaseSettings, password: str) -> None:
    """Create the capstone DB through the postgres maintenance database if needed.

    This function is for PowerShell CLI runs; an existing Jupyter `engine`
    already targets the database and does not need this bootstrap.
    """
    conn = psycopg2.connect(
        dbname="postgres", host=settings.host, port=settings.port,
        user=settings.username, password=password,
    )
    try:
        conn.autocommit = True  # CREATE DATABASE cannot run in a transaction.
        with conn.cursor() as cursor:
            cursor.execute("SELECT 1 FROM pg_database WHERE datname = %s", (settings.name,))
            if cursor.fetchone():
                print(f"Database {settings.name} already exists")
            else:
                cursor.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(settings.name)))
                print(f"Created database {settings.name}")
    finally:
        conn.close()


def create_db_engine(settings: DatabaseSettings, password: str) -> Engine:
    url = URL.create(
        "postgresql+psycopg2",
        username=settings.username,
        password=password,
        host=settings.host,
        port=settings.port,
        database=settings.name,
    )
    return create_engine(url, pool_pre_ping=True)
