-- =====================================================================
-- 02_views_evm.sql   <-- YOU WRITE THIS FILE
--
-- Goal: calculate Earned Value Management (EVM) metrics with SQL views.
-- Build the views in order. After each one, re-run:
--       python src/load_db.py
-- then check the result in VS Code (open program.db with SQLite Viewer)
-- or with a quick query (see GUIDE.md -> "How to test a query").
--
-- Only months up to the status period count:
--       SELECT status_period FROM program_settings;   -- '2026-09'
-- =====================================================================


-- ---------------------------------------------------------------------
-- VIEW 1: v_monthly_pv
-- Planned Value per PROJECT per MONTH.
-- Output columns: project_id, period, pv
--
-- Hints:
--   * baseline_plan has planned_value per activity per period
--   * activities -> wbs -> projects (join on wbs_id to get project_id)
--   * GROUP BY project_id, period
--   * keep only period <= the status period
-- ---------------------------------------------------------------------
-- DROP VIEW IF EXISTS v_monthly_pv;
-- CREATE VIEW v_monthly_pv AS
-- SELECT ...


-- ---------------------------------------------------------------------
-- VIEW 2: v_monthly_ac
-- Actual Cost per PROJECT per MONTH.
-- Output columns: project_id, period, ac
--
-- Hints: same pattern as VIEW 1, but from cost_actuals.
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- VIEW 3: v_activity_ev
-- Cumulative Earned Value per ACTIVITY per MONTH.
-- Output columns: activity_id, project_id, period, cum_ev
--
--   cum_ev = budget * pct_complete / 100
--
-- Hints:
--   * progress.pct_complete is ALREADY cumulative
--   * join progress -> activities (for budget) -> wbs (for project_id)
--
-- Careful (this is the tricky part of the whole project):
--   An activity that finished in March has NO progress rows after March,
--   but it still counts as 100% earned in April, May, ...
--   If you just SUM progress rows by month, finished activities "disappear".
--   Fix idea: build every (activity, month) combination with a CROSS JOIN of
--   activities and the list of months, then for each one pick the latest
--   progress row with period <= that month (a correlated subquery with
--   ORDER BY period DESC LIMIT 1 works in SQLite).
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- VIEW 4: v_project_evm          (the report reads this view)
-- Cumulative PV, EV, AC per PROJECT per MONTH.
-- Output columns: project_id, period, cum_pv, cum_ev, cum_ac
--
-- Hints:
--   * cum_ev = SUM of v_activity_ev.cum_ev per project/month (already cumulative)
--   * cum_pv and cum_ac need a WINDOW FUNCTION:
--         SUM(pv) OVER (PARTITION BY project_id ORDER BY period)
--   * use LEFT JOINs so months with no cost still appear
-- ---------------------------------------------------------------------


-- ---------------------------------------------------------------------
-- VIEW 5: v_project_status       (the report reads this view)
-- One row per project at the STATUS PERIOD.
-- Output columns:
--   project_id, name, bac, cum_pv, cum_ev, cum_ac,
--   cv, sv, cpi, spi, eac, etc, vac, pct_complete, status
--
--   BAC = SUM(activities.budget) for the project
--   CV  = EV - AC            SV  = EV - PV
--   CPI = EV / AC            SPI = EV / PV
--   EAC = BAC / CPI          ETC = EAC - AC          VAC = BAC - EAC
--   pct_complete = EV / BAC * 100
--   status = 'Red'   if CPI < 0.90 or SPI < 0.80
--            'Amber' if CPI < 0.97 or SPI < 0.95
--            'Green' otherwise                    (use CASE WHEN)
--
-- Watch out for integer division and divide-by-zero (NULLIF(x, 0)).
-- ---------------------------------------------------------------------
