-- =====================================================================
-- 03_analysis.sql   <-- YOU WRITE THESE QUERIES (after 02_views_evm.sql works)
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


-- Q2. Which TRADES are driving cost overruns?
--     For each trade across the whole program: total EV, total AC, cost variance (EV - AC)
--     and trade CPI. Sort by the biggest overrun.
--     Hint: use activity-level EV at the status period (v_activity_ev) and
--     SUM of cost_actuals per activity, then GROUP BY trade.


-- Q3. Which activities are late?
--     Activities whose baseline_finish is on or before the status period but are
--     not 100% complete. Show project, activity, trade, baseline_finish, % complete.


-- Q4. Change orders by root cause.
--     For each reason: number of COs, total $, share of total $ (percent).
--     Only count Approved + Pending (Rejected COs didn't change the contract).


-- Q5. How long do change orders take to approve?
--     Average and maximum days from submitted_date to approved_date, per project.
--     Hint: julianday(approved_date) - julianday(submitted_date)


-- Q6. Contract position per project.
--     original contract_value, approved CO $, pending CO $,
--     current contract = original + approved, and potential = current + pending.


-- Q7. Buyout check: are commitments covering the budget?
--     Per project and trade: activity budget vs committed amount, and the gap.
--     Positive gap = scope bought for more than budgeted.


-- Q8. (Stretch) Monthly burn rate.
--     Average monthly actual cost over the last 3 months per project, and the
--     months of work left at that rate:  (EAC - AC) / avg monthly cost.
--     Hint: window functions or a subquery filtered to the last 3 periods.
