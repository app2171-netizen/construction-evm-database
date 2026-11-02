-- =====================================================================
-- 01_schema.sql
-- Construction program controls database (SQLite)
--
-- One PROGRAM contains several PROJECTS.
-- Each project is broken into a WBS, and each WBS element into ACTIVITIES.
-- Activities carry the budget; everything else (plan, progress, cost)
-- is recorded per activity per month ("period" = 'YYYY-MM').
-- =====================================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS change_orders;
DROP TABLE IF EXISTS commitments;
DROP TABLE IF EXISTS cost_actuals;
DROP TABLE IF EXISTS progress;
DROP TABLE IF EXISTS baseline_plan;
DROP TABLE IF EXISTS activities;
DROP TABLE IF EXISTS wbs;
DROP TABLE IF EXISTS projects;
DROP TABLE IF EXISTS program_settings;

-- Single-row table holding the reporting cut-off month
CREATE TABLE program_settings (
    program_name   TEXT NOT NULL,
    status_period  TEXT NOT NULL            -- last month with actuals, 'YYYY-MM'
);

CREATE TABLE projects (
    project_id      TEXT PRIMARY KEY,       -- e.g. 'P01'
    name            TEXT NOT NULL,
    project_type    TEXT NOT NULL,          -- Bridge, Rail, Roadway, ...
    borough         TEXT,
    owner           TEXT,
    contractor      TEXT,
    contract_value  REAL NOT NULL,          -- original contract amount ($)
    baseline_start  TEXT NOT NULL,          -- 'YYYY-MM-DD'
    baseline_finish TEXT NOT NULL
);

CREATE TABLE wbs (
    wbs_id      TEXT PRIMARY KEY,           -- e.g. 'P01-2'
    project_id  TEXT NOT NULL REFERENCES projects(project_id),
    wbs_code    TEXT NOT NULL,              -- e.g. '2'
    wbs_name    TEXT NOT NULL               -- e.g. 'Substructure'
);

CREATE TABLE activities (
    activity_id     TEXT PRIMARY KEY,       -- e.g. 'P01-A07'
    wbs_id          TEXT NOT NULL REFERENCES wbs(wbs_id),
    activity_name   TEXT NOT NULL,
    trade           TEXT NOT NULL,          -- Civil, Concrete, Steel, Electrical, ...
    baseline_start  TEXT NOT NULL,          -- first month of work, 'YYYY-MM'
    baseline_finish TEXT NOT NULL,          -- last month of work,  'YYYY-MM'
    budget          REAL NOT NULL           -- Budget at Completion for this activity ($)
);

-- Time-phased baseline budget (what a cost-loaded P6 schedule exports).
-- SUM(planned_value) over all periods = activities.budget
CREATE TABLE baseline_plan (
    activity_id    TEXT NOT NULL REFERENCES activities(activity_id),
    period         TEXT NOT NULL,           -- 'YYYY-MM'
    planned_value  REAL NOT NULL,           -- budget planned to be earned that month ($)
    PRIMARY KEY (activity_id, period)
);

-- Reported progress. pct_complete is CUMULATIVE (0-100) as of the end of the period.
CREATE TABLE progress (
    activity_id   TEXT NOT NULL REFERENCES activities(activity_id),
    period        TEXT NOT NULL,
    pct_complete  REAL NOT NULL CHECK (pct_complete BETWEEN 0 AND 100),
    PRIMARY KEY (activity_id, period)
);

-- Actual cost booked against the activity in that month (NOT cumulative).
CREATE TABLE cost_actuals (
    activity_id  TEXT NOT NULL REFERENCES activities(activity_id),
    period       TEXT NOT NULL,
    actual_cost  REAL NOT NULL,
    PRIMARY KEY (activity_id, period)
);

-- Subcontracts / purchase orders awarded.
CREATE TABLE commitments (
    commitment_id  TEXT PRIMARY KEY,
    project_id     TEXT NOT NULL REFERENCES projects(project_id),
    vendor         TEXT NOT NULL,
    trade          TEXT NOT NULL,
    amount         REAL NOT NULL,
    award_date     TEXT NOT NULL
);

CREATE TABLE change_orders (
    co_id          TEXT PRIMARY KEY,
    project_id     TEXT NOT NULL REFERENCES projects(project_id),
    description    TEXT NOT NULL,
    reason         TEXT NOT NULL,           -- Design Error, Owner Request, Unforeseen Condition, Regulatory
    trade          TEXT NOT NULL,
    status         TEXT NOT NULL,           -- Approved, Pending, Rejected
    amount         REAL NOT NULL,
    submitted_date TEXT NOT NULL,
    approved_date  TEXT                     -- NULL unless Approved
);

CREATE INDEX idx_wbs_project      ON wbs(project_id);
CREATE INDEX idx_act_wbs          ON activities(wbs_id);
CREATE INDEX idx_plan_period      ON baseline_plan(period);
CREATE INDEX idx_progress_period  ON progress(period);
CREATE INDEX idx_cost_period      ON cost_actuals(period);
