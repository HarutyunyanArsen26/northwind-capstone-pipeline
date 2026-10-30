"""Download missing Northwind source CSVs from the referenced GitHub repository.

The repository used for this capstone provides 11 CSVs, not the 13 mentioned
in the ACA assignment. The two extra tables require instructor clarification.
"""

from __future__ import annotations

import csv
import io
from pathlib import Path
from urllib.request import urlopen

from .stage_raw_data import TABLES

BASE_URL = (
    "https://raw.githubusercontent.com/graphql-compose/"
    "graphql-compose-examples/master/examples/northwind/data/csv"
)


def ensure_source_csvs(raw_dir: Path, refresh: bool = False) -> dict[str, Path]:
    """Keep existing CSVs or download missing files; optionally refresh all.

    No data is altered during download. An incomplete download is written to a
    temporary filename, checked for CSV structure, then atomically moved.
    """
    raw_dir = Path(raw_dir)
    raw_dir.mkdir(parents=True, exist_ok=True)
    paths: dict[str, Path] = {}
    for name in TABLES:
        target = raw_dir / f"{name}.csv"
        if not target.is_file() or refresh:
            url = f"{BASE_URL}/{name}.csv"
            print(f"Downloading {name}.csv from Northwind GitHub")
            with urlopen(url, timeout=30) as response:
                content = response.read()
            # Validate header and nonempty source, including unusual quoted CSVs.
            decoded = content.decode("utf-8-sig")
            rows = csv.reader(io.StringIO(decoded))
            header = next(rows, [])
            if not header or next(rows, None) is None:
                raise ValueError(f"Downloaded CSV is empty or has no data rows: {url}")
            temp = target.with_suffix(".csv.download")
            temp.write_bytes(content)
            temp.replace(target)
        paths[name] = target
    return paths
