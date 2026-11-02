# Step-by-step guide

You'll work through this project in VS Code. The data, database loader and charts are already
set up. **Your job is the SQL**: `sql/02_views_evm.sql` (the EVM engine) and `sql/03_analysis.sql`
(business questions).

> Commands below use `python`. On a Mac, type `python3` and `pip3` instead.

---

## 1. Get the project onto your computer

1. Open VS Code, then press **Ctrl+Shift+P** (Mac: **Cmd+Shift+P**), type **Git: Clone**, and press Enter.
2. Paste `https://github.com/app2171-netizen/construction-evm-database` and choose a folder, e.g. `Documents/GitHub`.
3. Click **Open** when VS Code asks.

*(No Git installed? On the GitHub page, click **Code → Download ZIP**, unzip it, and in VS Code use **File → Open Folder**.)*

## 2. Build the database

Open the terminal (**View → Terminal**) and run:

```bash
pip install -r requirements.txt
python src/generate_data.py      # creates data/*.csv
python src/load_db.py            # creates program.db
```

Click `program.db` in the file list. SQLite Viewer opens it so you can browse every table.
Spend 10 minutes looking around: `projects`, `activities`, `baseline_plan`, `progress`, `cost_actuals`.

**Understand the data before writing SQL:**
- `baseline_plan` is the cost-loaded schedule: how much budget each activity *should* earn each month.
- `progress.pct_complete` is **cumulative** (e.g. 18 → 44 → 74 → 100).
- `cost_actuals.actual_cost` is **monthly** (not cumulative).
- The status period (data cut-off) is **2026-09**.

## 3. How to test a query

Fastest way, from the terminal:

```bash
python src/run_query.py "SELECT * FROM projects"
```

Workflow for each view: write it in `02_views_evm.sql`, run `python src/load_db.py`, then
`python src/run_query.py "SELECT * FROM v_monthly_pv LIMIT 10"`. If there's an error, `load_db.py` prints it.

## 4. Write the EVM views (`sql/02_views_evm.sql`)

Do them **in order**. Each view builds on the previous ones. Use these checkpoints to confirm you got it right:

| View | Check query | Expected |
|---|---|---|
| `v_monthly_pv` | `SELECT COUNT(*) FROM v_monthly_pv` | **65** rows |
| | PV for P01 in 2026-09 | **≈ $3,515,776** |
| `v_monthly_ac` | `SELECT COUNT(*) FROM v_monthly_ac` | **59** rows |
| | AC for P01 in 2026-09 | **≈ $3,571,059** |
| `v_activity_ev` | cum_ev for `P01-A03` in 2026-06 | **$3,262,000**. It finished in March, but it must still count in June. This is the tricky one |
| | `SELECT SUM(cum_ev) FROM v_activity_ev WHERE period='2026-09'` | **≈ $121,975,119** |
| `v_project_evm` | `SELECT COUNT(*) FROM v_project_evm` | **75** rows (5 projects × 15 months) |
| | P01 at 2026-09 | PV ≈ 31.01M, EV ≈ 31.33M, AC ≈ 30.95M |
| `v_project_status` | P01 | CPI ≈ **1.01**, SPI ≈ **1.01**, Green |
| | P05 | CPI ≈ **0.82**, SPI ≈ **0.62**, EAC ≈ **$97.9M**, Red |

> Your exact numbers depend on how you build the month list for `v_activity_ev`. If your row
> counts differ slightly but CPI/SPI match to 2 decimals, you're fine.

**SQL concepts you'll practice:** JOINs across 3 tables, GROUP BY, CTEs (`WITH ...`), CROSS JOIN,
correlated subqueries, window functions (`SUM() OVER (PARTITION BY ... ORDER BY ...)`), `CASE WHEN`, `NULLIF`.

## 5. Run the report

```bash
python src/load_db.py
python src/report.py
```

This creates `outputs/s_curves.png`, `outputs/portfolio_cpi_spi.png` and `outputs/portfolio_status.csv`.
Open the PNGs in VS Code and check they make sense. Which project looks healthy? Which is in trouble, and is the problem cost, schedule, or both?

## 6. Answer the business questions (`sql/03_analysis.sql`)

Write one query per question, then run them all:

```bash
python src/run_query.py --file sql/03_analysis.sql
```

Under each query, write a one-line comment with what you found. These become the **Key findings** in your README.

## 7. Finish the README and publish

Replace the "Results" placeholders in `README.md` with your charts and findings, then commit and push.
In VS Code, open the **Source Control** tab (the branch icon), type a message, then click **Commit** and **Sync**.

---

### Stuck?
Send me the SQL you wrote and the error message. I'll explain what's wrong, but I won't just hand you the
answer, because you'll need to explain these queries in interviews.
