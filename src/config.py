"""Shared configuration for ACA Northwind Capstone.

Never put a database password into source control or a notebook cell.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = PROJECT_ROOT / "data" / "raw"
SQL_DIR = PROJECT_ROOT / "sql"


@dataclass(frozen=True)
class DatabaseSettings:
    host: str = "localhost"
    port: int = 5432
    name: str = "northwind_capstone"
    username: str = "postgres"


def get_database_settings() -> DatabaseSettings:
    """Read non-secret connection settings from environment variables."""
    return DatabaseSettings(
        host=os.environ.get("CAPSTONE_DB_HOST", "localhost"),
        port=int(os.environ.get("CAPSTONE_DB_PORT", "5432")),
        name=os.environ.get("CAPSTONE_DB_NAME", "northwind_capstone"),
        username=os.environ.get("CAPSTONE_DB_USER", "postgres"),
    )
