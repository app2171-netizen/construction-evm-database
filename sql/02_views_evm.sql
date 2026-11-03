-- =====================================================================
-- 02_views_evm.sql   Earned Value Management (EVM) views
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
DROP VIEW IF EXISTS v_monthly_pv;
CREATE VIEW v_monthly_pv AS
SELECT
    w.project_id,
    b.period,
    SUM(b.planned_value) AS pv
FROM baseline_plan AS b
JOIN activities AS a ON a.activity_id = b.activity_id
JOIN wbs        AS w ON w.wbs_id      = a.wbs_id
WHERE b.period <= (SELECT status_period FROM program_settings)
GROUP BY w.project_id, b.period;


-- ---------------------------------------------------------------------
-- VIEW 2: v_monthly_ac
-- Actual Cost per PROJECT per MONTH.
-- Output columns: project_id, period, ac
--
-- Hints: same pattern as VIEW 1, but from cost_actuals.
DROP VIEW IF EXISTS v_monthly_ac;
CREATE VIEW v_monthly_ac AS
SELECT
    w.project_id,
    c.period,
    SUM(c.actual_cost) AS ac
FROM cost_actuals AS c
JOIN activities AS a ON a.activity_id = c.activity_id
JOIN wbs        AS w ON w.wbs_id      = a.wbs_id
WHERE c.period <= (SELECT status_period FROM program_settings)
GROUP BY w.project_id, c.period;


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
DROP VIEW IF EXISTS v_activity_ev;
CREATE VIEW v_activity_ev AS
WITH months AS (
    SELECT period FROM baseline_plan
    UNION
    SELECT period FROM progress
),
grid AS (
    SELECT a.activity_id, w.project_id, a.budget, m.period
    FROM activities AS a
    JOIN wbs AS w ON w.wbs_id = a.wbs_id
    CROSS JOIN months AS m
    WHERE m.period <= (SELECT status_period FROM program_settings)
)
SELECT
    g.activity_id,
    g.project_id,
    g.period,
    g.budget * COALESCE((
        SELECT p.pct_complete
        FROM progress AS p
        WHERE p.activity_id = g.activity_id
          AND p.period <= g.period
        ORDER BY p.period DESC
        LIMIT 1
    ), 0) / 100.0 AS cum_ev
FROM grid AS g;


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
DROP VIEW IF EXISTS v_project_evm;
CREATE VIEW v_project_evm AS
WITH ev AS (
    SELECT project_id, period, SUM(cum_ev) AS cum_ev
    FROM v_activity_ev
    GROUP BY project_id, period
)
SELECT
    ev.project_id,
    ev.period,
    SUM(COALESCE(pv.pv, 0)) OVER (PARTITION BY ev.project_id ORDER BY ev.period) AS cum_pv,
    ev.cum_ev,
    SUM(COALESCE(ac.ac, 0)) OVER (PARTITION BY ev.project_id ORDER BY ev.period) AS cum_ac
FROM ev
LEFT JOIN v_monthly_pv AS pv ON pv.project_id = ev.project_id AND pv.period = ev.period
LEFT JOIN v_monthly_ac AS ac ON ac.project_id = ev.project_id AND ac.period = ev.period;

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
DROP VIEW IF EXISTS v_project_status;
CREATE VIEW v_project_status AS
WITH bac AS (                                   -- total budget per project
    SELECT w.project_id, SUM(a.budget) AS bac
    FROM activities AS a
    JOIN wbs AS w ON w.wbs_id = a.wbs_id
    GROUP BY w.project_id
),
cur AS (                                        -- only the status month
    SELECT * FROM v_project_evm
    WHERE period = (SELECT status_period FROM program_settings)
),
m AS (                                          -- basic metrics
    SELECT p.project_id, p.name, b.bac, c.cum_pv, c.cum_ev, c.cum_ac,
           c.cum_ev - c.cum_ac                 AS cv,
           c.cum_ev - c.cum_pv                 AS sv,
           c.cum_ev / NULLIF(c.cum_ac, 0)      AS cpi,
           c.cum_ev / NULLIF(c.cum_pv, 0)      AS spi
    FROM projects AS p
    JOIN bac AS b ON b.project_id = p.project_id
    JOIN cur AS c ON c.project_id = p.project_id
)
SELECT m.*,
       bac / cpi            AS eac,
       bac / cpi - cum_ac   AS etc,
       bac - bac / cpi      AS vac,
       100.0 * cum_ev / bac AS pct_complete,
       CASE
           WHEN cpi < 0.90 OR spi < 0.80 THEN 'Red'
           WHEN cpi < 0.97 OR spi < 0.95 THEN 'Amber'
           ELSE 'Green'
       END AS status
FROM m;
