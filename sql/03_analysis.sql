-- =====================================================================
-- 03_analysis.sql   Program management questions answered with SQL
--
-- Business questions a program manager would ask. Write one query per
-- question, run it, and note the answer in a comment under the query.
-- Your best findings go into the README.
--
-- Run a single query from the terminal with:
--     python src/run_query.py "SELECT ..."
-- =====================================================================


-- Q1. Which projects are in trouble?
--     List projects with CPI < 0.95 OR SPI < 0.95, worst CPI first.
--     Show name, CPI, SPI, EAC and VAC (VAC in $ millions, 1 decimal).
SELECT name,
       ROUND(cpi, 2)        AS cpi,
       ROUND(spi, 2)        AS spi,
       ROUND(eac / 1e6, 1)  AS eac_m,
       ROUND(vac / 1e6, 1)  AS vac_m
FROM v_project_status
WHERE cpi < 0.95 OR spi < 0.95
ORDER BY cpi;

-- FINDINGS: 3 of 5 projects need attention.
--   * Canal Avenue Viaduct (P05) is the problem job: CPI 0.82 and SPI 0.62 -> over budget AND
--     behind. Forecast to finish at $97.9M vs $80.3M budget (-$17.6M).
--   * Eastline Station (P02): CPI 0.89 -> ~$4.2M overrun forecast, also slipping (SPI 0.86).
--   * Riverside Drive (P03): cost is fine (CPI 1.02) but badly behind schedule (SPI 0.55).


-- Q2. Which TRADES are driving cost overruns?
--     For each trade across the whole program: total EV, total AC, cost variance (EV - AC)
--     and trade CPI. Sort by the biggest overrun.
--     Hint: use activity-level EV at the status period (v_activity_ev) and
--     SUM of cost_actuals per activity, then GROUP BY trade.
WITH act AS (
    SELECT a.activity_id, a.trade,
           (SELECT cum_ev FROM v_activity_ev e
             WHERE e.activity_id = a.activity_id
               AND e.period = (SELECT status_period FROM program_settings)) AS ev,
           COALESCE((SELECT SUM(actual_cost) FROM cost_actuals c
                      WHERE c.activity_id = a.activity_id), 0) AS ac
    FROM activities AS a
)
SELECT trade,
       ROUND(SUM(ev) / 1e6, 2)                AS ev_m,
       ROUND(SUM(ac) / 1e6, 2)                AS ac_m,
       ROUND((SUM(ev) - SUM(ac)) / 1e6, 2)    AS cv_m,
       ROUND(SUM(ev) / NULLIF(SUM(ac), 0), 2) AS cpi
FROM act
GROUP BY trade
HAVING SUM(ac) > 0
ORDER BY cv_m ASC;

-- FINDINGS: Concrete is the biggest overrun driver (-$3.9M, CPI 0.91), followed by Steel (-$1.9M)
--   and Civil (-$1.7M). Elevator has the worst efficiency (CPI 0.84) but on a smaller base.
--   Only Utilities is under budget (CPI 1.03).


-- Q3. Which activities are late?
--     Activities whose baseline_finish is on or before the status period but are
--     not 100% complete. Show project, activity, trade, baseline_finish, % complete.
SELECT w.project_id, a.activity_name, a.trade, a.baseline_finish,
       ROUND(100.0 * e.cum_ev / a.budget, 1) AS pct_complete
FROM activities AS a
JOIN wbs AS w ON w.wbs_id = a.wbs_id
JOIN v_activity_ev AS e ON e.activity_id = a.activity_id
WHERE e.period = (SELECT status_period FROM program_settings)
  AND a.baseline_finish <= (SELECT status_period FROM program_settings)
  AND e.cum_ev < a.budget
ORDER BY a.baseline_finish, pct_complete;

-- FINDINGS: 6 activities are past their baseline finish and not complete. P03 has 3 of them, including
--   Excavation & base at only 14% when it should be done -> explains P03's SPI of 0.55.
--   P05's pier and abutment concrete are also overdue (80-87% complete).


-- Q4. Change orders by root cause.
--     For each reason: number of COs, total $, share of total $ (percent).
--     Only count Approved + Pending (Rejected COs didn't change the contract).
SELECT reason,
       COUNT(*)    AS num_cos,
       SUM(amount) AS total_usd,
       ROUND(100.0 * SUM(amount) /
             (SELECT SUM(amount) FROM change_orders WHERE status IN ('Approved', 'Pending')), 1) AS pct_of_total
FROM change_orders
WHERE status IN ('Approved', 'Pending')
GROUP BY reason
ORDER BY total_usd DESC;

-- FINDINGS: Unforeseen conditions are the #1 cause (37% of CO dollars, $5.1M), then owner requests
--   (32%). Design errors account for 21% ($2.9M) - a recoverable cost to raise with the designer.


-- Q5. How long do change orders take to approve?
--     Average and maximum days from submitted_date to approved_date, per project.
--     Hint: julianday(approved_date) - julianday(submitted_date)
SELECT p.project_id, p.name,
       COUNT(*) AS approved_cos,
       ROUND(AVG(julianday(co.approved_date) - julianday(co.submitted_date)), 0) AS avg_days,
       MAX(julianday(co.approved_date) - julianday(co.submitted_date))           AS max_days
FROM change_orders AS co
JOIN projects AS p ON p.project_id = co.project_id
WHERE co.status = 'Approved'
GROUP BY p.project_id, p.name
ORDER BY avg_days DESC;

-- FINDINGS: P05 takes the longest to approve changes (avg 47 days, max 60). P04 has the most approved
--   COs (8) and the single slowest approval (72 days). Slow approvals delay payment and work.


-- Q6. Contract position per project.
--     original contract_value, approved CO $, pending CO $,
--     current contract = original + approved, and potential = current + pending.
SELECT p.project_id, p.name,
       p.contract_value AS original,
       SUM(CASE WHEN co.status = 'Approved' THEN co.amount ELSE 0 END) AS approved_cos,
       SUM(CASE WHEN co.status = 'Pending'  THEN co.amount ELSE 0 END) AS pending_cos,
       p.contract_value + SUM(CASE WHEN co.status = 'Approved' THEN co.amount ELSE 0 END) AS current_contract,
       p.contract_value + SUM(CASE WHEN co.status IN ('Approved', 'Pending') THEN co.amount ELSE 0 END) AS potential_contract
FROM projects AS p
LEFT JOIN change_orders AS co ON co.project_id = p.project_id
GROUP BY p.project_id, p.name, p.contract_value
ORDER BY p.project_id;

-- FINDINGS: P04 has grown the most: +$5.5M approved (+8.8%) with $0.7M more pending.
--   P05 has $2.2M pending - if approved, its contract reaches $89.1M.


-- Q7. Buyout check: are commitments covering the budget?
--     Per project and trade: activity budget vs committed amount, and the gap.
--     Positive gap = scope bought for more than budgeted.
WITH budget AS (
    SELECT w.project_id, a.trade, SUM(a.budget) AS budget
    FROM activities AS a
    JOIN wbs AS w ON w.wbs_id = a.wbs_id
    GROUP BY w.project_id, a.trade
),
committed AS (
    SELECT project_id, trade, SUM(amount) AS committed
    FROM commitments
    GROUP BY project_id, trade
)
SELECT b.project_id, b.trade, b.budget,
       COALESCE(c.committed, 0)             AS committed,
       COALESCE(c.committed, 0) - b.budget  AS gap,
       ROUND(100.0 * (COALESCE(c.committed, 0) - b.budget) / b.budget, 1) AS gap_pct
FROM budget AS b
LEFT JOIN committed AS c ON c.project_id = b.project_id AND c.trade = b.trade
ORDER BY gap DESC
LIMIT 10;

-- FINDINGS: Buyout is running over budget across the board. The biggest gap is P05 Concrete:
--   committed $2.5M (9.2%) above budget - matching Concrete being the top overrun trade in Q2.


-- Q8. (Stretch) Monthly burn rate.
--     Average monthly actual cost over the last 3 months per project, and the
--     months of work left at that rate:  (EAC - AC) / avg monthly cost.
--     Hint: window functions or a subquery filtered to the last 3 periods.
WITH last3 AS (
    SELECT w.project_id, SUM(c.actual_cost) / 3.0 AS avg_monthly_cost
    FROM cost_actuals AS c
    JOIN activities AS a ON a.activity_id = c.activity_id
    JOIN wbs AS w ON w.wbs_id = a.wbs_id
    WHERE c.period > (SELECT period FROM (SELECT DISTINCT period FROM cost_actuals
                                          ORDER BY period DESC LIMIT 1 OFFSET 3))   -- 4th-latest month
    GROUP BY w.project_id
)
SELECT s.project_id, s.name,
       ROUND(l.avg_monthly_cost / 1e6, 2)                       AS burn_m_per_month,
       ROUND((s.eac - s.cum_ac) / 1e6, 1)                       AS remaining_m,
       ROUND((s.eac - s.cum_ac) / l.avg_monthly_cost, 1)        AS months_left
FROM v_project_status AS s
JOIN last3 AS l ON l.project_id = s.project_id
ORDER BY months_left DESC;

-- FINDINGS: P05 is burning $5.2M/month with $61.3M left to spend (at its current CPI) -> ~12 months
--   of work remaining. P01 is closest to completion (~3 months at current burn).
