"""
run_query.py
Quickly run any SQL against program.db and print the result as a table.

Examples:
    python src/run_query.py "SELECT * FROM projects"
    python src/run_query.py "SELECT * FROM v_project_status"
    python src/run_query.py --file sql/03_analysis.sql      (runs every query in the file)
"""

import sqlite3
import sys
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "program.db"

pd.set_option("display.width", 200)
pd.set_option("display.max_columns", 30)
pd.set_option("display.float_format", lambda v: f"{v:,.2f}")


def split_queries(sql: str) -> list[str]:
    """Split a .sql file into statements, ignoring comment-only chunks."""
    out = []
    for chunk in sql.split(";"):
        code = "\n".join(l for l in chunk.splitlines() if not l.strip().startswith("--")).strip()
        if code:
            out.append(code)
    return out


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    conn = sqlite3.connect(DB_PATH)
    if sys.argv[1] == "--file":
        queries = split_queries(Path(sys.argv[2]).read_text(encoding="utf-8"))
    else:
        queries = [sys.argv[1]]
    for i, q in enumerate(queries, 1):
        print(f"\n--- Query {i} ---\n{q}\n")
        try:
            print(pd.read_sql(q, conn).to_string(index=False))
        except Exception as e:  # show the SQL error instead of crashing
            print(f"ERROR: {e}")
    conn.close()


if __name__ == "__main__":
    main()
