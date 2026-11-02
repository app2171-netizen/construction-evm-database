"""
report.py
Reads your EVM views and produces:
    outputs/s_curves.png         - cumulative PV / EV / AC for every project
    outputs/portfolio_cpi_spi.png - CPI vs SPI quadrant chart
    outputs/portfolio_status.csv  - one row per project with all EVM metrics

Needs v_project_evm and v_project_status from sql/02_views_evm.sql.

Run:  python src/report.py
"""

import sqlite3
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "program.db"
OUT = ROOT / "outputs"

COLORS = {"pv": "#2563eb", "ev": "#16a34a", "ac": "#dc2626"}
STATUS_COLORS = {"Green": "#16a34a", "Amber": "#d97706", "Red": "#dc2626"}


def require_views(conn):
    have = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='view'")}
    missing = {"v_project_evm", "v_project_status"} - have
    if missing:
        raise SystemExit(
            f"Missing view(s): {', '.join(sorted(missing))}.\n"
            "Write them in sql/02_views_evm.sql, then run `python src/load_db.py` again."
        )


def s_curves(evm: pd.DataFrame, names: dict):
    projects = list(evm["project_id"].unique())
    fig, axes = plt.subplots(len(projects), 1, figsize=(10, 3.2 * len(projects)), sharex=False)
    for ax, pid in zip(axes, projects):
        d = evm[evm["project_id"] == pid]
        ax.plot(d["period"], d["cum_pv"] / 1e6, label="Planned Value (PV)", color=COLORS["pv"], lw=2)
        ax.plot(d["period"], d["cum_ev"] / 1e6, label="Earned Value (EV)", color=COLORS["ev"], lw=2)
        ax.plot(d["period"], d["cum_ac"] / 1e6, label="Actual Cost (AC)", color=COLORS["ac"], lw=2, ls="--")
        ax.set_title(f"{pid} - {names[pid]}", loc="left", fontsize=11, fontweight="bold")
        ax.set_ylabel("$ millions")
        ax.grid(alpha=0.3)
        ax.tick_params(axis="x", rotation=45, labelsize=8)
    axes[0].legend(loc="upper left", fontsize=9)
    fig.tight_layout()
    fig.savefig(OUT / "s_curves.png", dpi=150)
    plt.close(fig)


def quadrant(status: pd.DataFrame):
    fig, ax = plt.subplots(figsize=(7, 6))
    ax.axhline(1, color="grey", lw=1)
    ax.axvline(1, color="grey", lw=1)
    for _, r in status.iterrows():
        ax.scatter(r["spi"], r["cpi"], s=r["bac"] / 1e5, color=STATUS_COLORS.get(r["status"], "grey"),
                   alpha=0.7, edgecolor="black")
        ax.annotate(r["project_id"], (r["spi"], r["cpi"]), xytext=(8, 4), textcoords="offset points")
    ax.set_xlabel("SPI (schedule performance)  ->  ahead")
    ax.set_ylabel("CPI (cost performance)  ->  under budget")
    ax.set_title("Portfolio health (bubble size = budget)")
    lo = min(0.5, status["spi"].min() - 0.05, status["cpi"].min() - 0.05)
    ax.set_xlim(lo, 1.2)
    ax.set_ylim(lo, 1.2)
    ax.text(lo + 0.02, lo + 0.02, "Behind & over budget", color="#dc2626", fontsize=9)
    ax.text(1.02, 1.17, "Ahead & under budget", color="#16a34a", fontsize=9, va="top")
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(OUT / "portfolio_cpi_spi.png", dpi=150)
    plt.close(fig)


def main():
    OUT.mkdir(exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    require_views(conn)

    evm = pd.read_sql("SELECT * FROM v_project_evm ORDER BY project_id, period", conn)
    status = pd.read_sql("SELECT * FROM v_project_status ORDER BY project_id", conn)
    names = dict(conn.execute("SELECT project_id, name FROM projects").fetchall())
    conn.close()

    s_curves(evm, names)
    quadrant(status)
    status.to_csv(OUT / "portfolio_status.csv", index=False)

    cols = ["project_id", "bac", "cum_ev", "cum_ac", "cpi", "spi", "eac", "vac", "status"]
    show = status[cols].copy()
    for c in ["bac", "cum_ev", "cum_ac", "eac", "vac"]:
        show[c] = (show[c] / 1e6).round(1)
    show[["cpi", "spi"]] = show[["cpi", "spi"]].round(2)
    print("\nPortfolio status ($ millions)\n")
    print(show.to_string(index=False))
    print(f"\nCharts and CSV saved to {OUT}")


if __name__ == "__main__":
    main()
