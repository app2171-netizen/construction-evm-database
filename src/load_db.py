"""
load_db.py
Builds program.db: creates the tables from sql/01_schema.sql, loads every CSV in
./data/, then runs the view scripts (02_views_evm.sql) if they contain any SQL.

Run:  python src/load_db.py
"""

import csv
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
SQL_DIR = ROOT / "sql"
DB_PATH = ROOT / "program.db"

# Load order matters because of foreign keys (parents before children)
TABLES = ["program_settings", "projects", "wbs", "activities", "baseline_plan",
          "progress", "cost_actuals", "commitments", "change_orders"]


def load_table(conn: sqlite3.Connection, table: str) -> int:
    path = DATA_DIR / f"{table}.csv"
    with open(path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        cols = reader.fieldnames
        rows = [[(r[c] if r[c] != "" else None) for c in cols] for r in reader]
    placeholders = ", ".join("?" for _ in cols)
    conn.executemany(f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({placeholders})", rows)
    return len(rows)


def run_sql_file(conn: sqlite3.Connection, name: str):
    path = SQL_DIR / name
    sql = path.read_text(encoding="utf-8")
    # Skip files that only contain comments (e.g. your TODO file before you start)
    code = "\n".join(line for line in sql.splitlines() if not line.strip().startswith("--")).strip()
    if code:
        conn.executescript(sql)
        print(f"  ran {name}")
    else:
        print(f"  skipped {name} (no SQL yet)")


def main():
    if not (DATA_DIR / "projects.csv").exists():
        raise SystemExit("No data found. Run `python src/generate_data.py` first.")

    if DB_PATH.exists():
        DB_PATH.unlink()
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys = ON")

    print("Creating schema ...")
    conn.executescript((SQL_DIR / "01_schema.sql").read_text(encoding="utf-8"))

    print("Loading data ...")
    for t in TABLES:
        print(f"  {t:<17} {load_table(conn, t):>5} rows")
    conn.commit()

    print("Creating views ...")
    run_sql_file(conn, "02_views_evm.sql")
    conn.commit()
    conn.close()
    print(f"Done -> {DB_PATH}")


if __name__ == "__main__":
    main()
