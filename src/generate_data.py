"""
generate_data.py
Creates realistic (fictional) data for a 5-project NYC infrastructure program
and writes one CSV per table into ./data/.

Each project gets a "personality" so the EVM analysis has real problems to find:
    healthy        - on budget, on schedule
    over_budget    - progressing on time but costing more than earned
    behind         - costs fine, but work started late and is moving slowly
    change_heavy   - lots of owner/design change orders
    troubled       - over budget AND behind schedule

Run:  python src/generate_data.py
"""

import csv
import random
from datetime import date
from pathlib import Path

SEED = 42
STATUS_PERIOD = "2026-09"          # last month with actual cost / progress
PROGRAM_NAME = "Metro NY Infrastructure Renewal Program (fictional)"

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"

# ---------------------------------------------------------------------------
# Project definitions (all names are fictional)
# ---------------------------------------------------------------------------
PROJECTS = [
    # id,  name,                               type,      borough,        start,     months, personality
    ("P01", "Harbor Street Bridge Rehabilitation", "Bridge",  "Staten Island", "2025-10", 20, "healthy"),
    ("P02", "Eastline Station Accessibility Upgrade", "Rail", "Bronx",         "2025-08", 22, "over_budget"),
    ("P03", "Riverside Drive Reconstruction",     "Roadway", "Manhattan",     "2025-11", 18, "behind"),
    ("P04", "Northgate Bus Depot Modernization",  "Facility", "Queens",       "2025-09", 24, "change_heavy"),
    ("P05", "Canal Avenue Viaduct Replacement",   "Bridge",  "Brooklyn",      "2025-07", 26, "troubled"),
]

PERSONALITY = {
    #               cost factor (AC/EV), start delay (months), production rate, CO count
    "healthy":      dict(cost=(0.96, 1.03), delay=(0, 0), rate=(0.97, 1.03), cos=(2, 3)),
    "over_budget":  dict(cost=(1.10, 1.22), delay=(0, 1), rate=(0.95, 1.02), cos=(3, 5)),
    "behind":       dict(cost=(0.97, 1.04), delay=(1, 3), rate=(0.70, 0.85), cos=(2, 4)),
    "change_heavy": dict(cost=(1.02, 1.08), delay=(0, 1), rate=(0.90, 0.98), cos=(9, 12)),
    "troubled":     dict(cost=(1.12, 1.25), delay=(1, 3), rate=(0.70, 0.85), cos=(5, 7)),
}

# WBS template per project type: (wbs name, [(activity, trade, share of budget, phase 0..1)])
# "phase" places the activity in the project timeline (0 = start, 1 = end).
WBS_TEMPLATES = {
    "Bridge": [
        ("General Conditions", [("Mobilization & MPT", "General", 0.04, 0.0), ("Site management", "General", 0.05, 0.5)]),
        ("Substructure", [("Cofferdams & dewatering", "Civil", 0.07, 0.10), ("Pier repairs", "Concrete", 0.10, 0.25),
                          ("Abutment reconstruction", "Concrete", 0.09, 0.30)]),
        ("Superstructure", [("Steel girder replacement", "Steel", 0.18, 0.45), ("Bearing replacement", "Steel", 0.05, 0.50),
                            ("Deck replacement", "Concrete", 0.16, 0.60)]),
        ("Systems & Finishes", [("Lighting & ITS", "Electrical", 0.07, 0.75), ("Drainage", "Civil", 0.05, 0.70),
                                ("Paving & striping", "Paving", 0.06, 0.85), ("Painting & coatings", "Painting", 0.05, 0.80)]),
        ("Closeout", [("Punch list & demob", "General", 0.03, 1.0)]),
    ],
    "Rail": [
        ("General Conditions", [("Mobilization & track access", "General", 0.05, 0.0), ("Site management", "General", 0.05, 0.5)]),
        ("Structural", [("Elevator shafts excavation", "Civil", 0.10, 0.15), ("Shaft structures", "Concrete", 0.12, 0.30),
                        ("Platform extensions", "Concrete", 0.10, 0.40)]),
        ("Vertical Transportation", [("Elevator installation", "Elevator", 0.17, 0.60), ("Stair & canopy steel", "Steel", 0.08, 0.50)]),
        ("Systems", [("Power & lighting", "Electrical", 0.11, 0.65), ("Communications & PA", "Electrical", 0.06, 0.75),
                     ("Fire alarm", "Electrical", 0.04, 0.80)]),
        ("Finishes & Closeout", [("ADA finishes & wayfinding", "Architectural", 0.05, 0.85), ("Testing & commissioning", "Commissioning", 0.04, 0.95)]),
    ],
    "Roadway": [
        ("General Conditions", [("Mobilization & MPT", "General", 0.06, 0.0), ("Site management", "General", 0.05, 0.5)]),
        ("Utilities", [("Water main replacement", "Utilities", 0.15, 0.15), ("Sewer upgrades", "Utilities", 0.13, 0.25),
                       ("Electrical conduit", "Electrical", 0.07, 0.35)]),
        ("Roadway", [("Excavation & base", "Civil", 0.14, 0.45), ("Curb & sidewalk", "Concrete", 0.12, 0.60),
                     ("Asphalt paving", "Paving", 0.12, 0.75)]),
        ("Finishes & Closeout", [("Street lighting & signals", "Electrical", 0.08, 0.80), ("Landscaping", "Landscape", 0.04, 0.90),
                                 ("Punch list & demob", "General", 0.04, 1.0)]),
    ],
    "Facility": [
        ("General Conditions", [("Mobilization", "General", 0.04, 0.0), ("Site management", "General", 0.05, 0.5)]),
        ("Structure", [("Demolition & abatement", "Demolition", 0.08, 0.10), ("Foundations", "Concrete", 0.09, 0.20),
                       ("Steel frame & roof", "Steel", 0.14, 0.35)]),
        ("MEP", [("HVAC & ventilation", "Mechanical", 0.13, 0.55), ("Electrical & EV charging", "Electrical", 0.17, 0.60),
                 ("Plumbing & fire protection", "Mechanical", 0.08, 0.55)]),
        ("Interiors & Closeout", [("Interior fit-out", "Architectural", 0.10, 0.75), ("Bus wash & lifts", "Equipment", 0.07, 0.80),
                                  ("Testing & commissioning", "Commissioning", 0.05, 0.95)]),
    ],
}

CONTRACT_VALUES = {"P01": 48e6, "P02": 36e6, "P03": 27e6, "P04": 62e6, "P05": 85e6}
OWNERS = {"Bridge": "NYC Department of Transportation (sample)", "Rail": "Metro Transit Authority (sample)",
          "Roadway": "NYC Department of Design & Construction (sample)", "Facility": "Metro Transit Authority (sample)"}
CONTRACTORS = ["Hudson Civil + Build", "Five Boroughs Constructors", "Empire Heavy Civil",
               "Liberty Infrastructure Group", "Atlantic Bridge & Rail"]
VENDOR_NAMES = {
    "General": ["Metro Site Services"], "Civil": ["Bedrock Excavation", "Tri-State Earthworks"],
    "Concrete": ["Keystone Concrete", "Granite City Formwork"], "Steel": ["Ironbridge Steel Erectors", "Harbor Steel Fabricators"],
    "Electrical": ["Volt Electrical Contractors", "Brightline Electric"], "Paving": ["Blacktop Paving Co."],
    "Painting": ["ShieldCoat Painting"], "Elevator": ["Vertex Elevator"], "Architectural": ["Cornerstone Interiors"],
    "Commissioning": ["Precision Commissioning"], "Utilities": ["Underground Utility Partners"],
    "Landscape": ["Greenway Landscaping"], "Demolition": ["Clearpath Demolition"],
    "Mechanical": ["AirFlow Mechanical", "Northstar Plumbing & Fire"], "Equipment": ["Fleet Equipment Systems"],
}
CO_TEMPLATES = [
    ("Design Error", "Revised {x} details after conflict found in field"),
    ("Design Error", "Missing {x} scope in contract drawings"),
    ("Owner Request", "Owner-requested upgrade to {x}"),
    ("Owner Request", "Added {x} scope requested by agency"),
    ("Unforeseen Condition", "Unforeseen subsurface conditions affecting {x}"),
    ("Unforeseen Condition", "Undocumented utilities encountered during {x}"),
    ("Regulatory", "Code / permit requirement change impacting {x}"),
]


# ---------------------------------------------------------------------------
# Month helpers ('YYYY-MM' strings)
# ---------------------------------------------------------------------------
def month_add(period: str, n: int) -> str:
    y, m = map(int, period.split("-"))
    total = y * 12 + (m - 1) + n
    return f"{total // 12:04d}-{total % 12 + 1:02d}"


def month_diff(a: str, b: str) -> int:
    """Number of months from a to b."""
    ya, ma = map(int, a.split("-"))
    yb, mb = map(int, b.split("-"))
    return (yb * 12 + mb) - (ya * 12 + ma)


def spread_s_curve(total: float, n: int) -> list[float]:
    """Split `total` over n months with a bell shape (slow start, peak, slow finish)."""
    if n == 1:
        return [total]
    weights = [1 + 2 * min(i + 0.5, n - i - 0.5) / n for i in range(n)]
    s = sum(weights)
    return [total * w / s for w in weights]


# ---------------------------------------------------------------------------
def generate():
    rng = random.Random(SEED)
    rows = {k: [] for k in ["program_settings", "projects", "wbs", "activities", "baseline_plan",
                            "progress", "cost_actuals", "commitments", "change_orders"]}
    rows["program_settings"].append(dict(program_name=PROGRAM_NAME, status_period=STATUS_PERIOD))
    co_counter = 1
    cm_counter = 1

    for (pid, name, ptype, borough, start, months, personality), contractor in zip(PROJECTS, CONTRACTORS):
        p = PERSONALITY[personality]
        contract = CONTRACT_VALUES[pid]
        finish = month_add(start, months - 1)
        rows["projects"].append(dict(
            project_id=pid, name=name, project_type=ptype, borough=borough, owner=OWNERS[ptype],
            contractor=contractor, contract_value=contract,
            baseline_start=f"{start}-01", baseline_finish=f"{finish}-28"))

        # Budget = contract minus ~6% (fee/contingency held outside activity budgets)
        budget_pool = contract * 0.94
        project_delay = rng.randint(*p["delay"])
        act_n = 0
        trade_budget = {}

        for w_idx, (wbs_name, acts) in enumerate(WBS_TEMPLATES[ptype], start=1):
            wbs_id = f"{pid}-{w_idx}"
            rows["wbs"].append(dict(wbs_id=wbs_id, project_id=pid, wbs_code=str(w_idx), wbs_name=wbs_name))

            for act_name, trade, share, phase in acts:
                act_n += 1
                aid = f"{pid}-A{act_n:02d}"
                budget = round(budget_pool * share * rng.uniform(0.92, 1.08), -3)

                # Baseline dates: general conditions span the whole job, others ~20-35% of duration
                if act_name.startswith("Site management"):
                    a_start, dur = start, months
                else:
                    dur = max(2, round(months * rng.uniform(0.18, 0.32)))
                    offset = round(phase * (months - dur))
                    a_start = month_add(start, offset)
                a_finish = month_add(a_start, dur - 1)
                rows["activities"].append(dict(
                    activity_id=aid, wbs_id=wbs_id, activity_name=act_name, trade=trade,
                    baseline_start=a_start, baseline_finish=a_finish, budget=budget))
                trade_budget[trade] = trade_budget.get(trade, 0) + budget

                # Baseline plan (time-phased budget)
                for i, pv in enumerate(spread_s_curve(budget, dur)):
                    rows["baseline_plan"].append(dict(activity_id=aid, period=month_add(a_start, i),
                                                      planned_value=round(pv, 2)))

                # ---- Actual performance up to the status period ----
                act_delay = project_delay + (rng.randint(0, 1) if personality in ("behind", "troubled") else 0)
                rate = rng.uniform(*p["rate"])
                cost_factor = rng.uniform(*p["cost"])
                actual_start = month_add(a_start, act_delay)
                actual_dur = max(1, round(dur / rate))
                planned_curve = spread_s_curve(100.0, actual_dur)

                cum_pct = 0.0
                for i in range(actual_dur):
                    period = month_add(actual_start, i)
                    if month_diff(period, STATUS_PERIOD) < 0:
                        break                                    # future month: no actuals yet
                    step = planned_curve[i] * rng.uniform(0.85, 1.15)
                    cum_pct = min(100.0, cum_pct + step)
                    if i == actual_dur - 1:
                        cum_pct = 100.0
                    earned_this_month = budget * step / 100
                    cost = earned_this_month * cost_factor * rng.uniform(0.92, 1.08)
                    rows["progress"].append(dict(activity_id=aid, period=period, pct_complete=round(cum_pct, 1)))
                    rows["cost_actuals"].append(dict(activity_id=aid, period=period, actual_cost=round(cost, 2)))

        # Commitments: one subcontract per trade, awarded near project start
        for trade, tb in trade_budget.items():
            vendor = rng.choice(VENDOR_NAMES.get(trade, ["Allied Contractors"]))
            award = month_add(start, rng.randint(0, max(1, months // 3)))
            rows["commitments"].append(dict(
                commitment_id=f"CM-{cm_counter:03d}", project_id=pid, vendor=vendor, trade=trade,
                amount=round(tb * rng.uniform(0.95, 1.12), -3), award_date=f"{award}-{rng.randint(1, 28):02d}"))
            cm_counter += 1

        # Change orders
        project_trades = list(trade_budget)
        for _ in range(rng.randint(*p["cos"])):
            reason, tmpl = rng.choice(CO_TEMPLATES)
            if personality == "change_heavy" and rng.random() < 0.5:
                reason, tmpl = rng.choice([t for t in CO_TEMPLATES if t[0] == "Owner Request"])
            trade = rng.choice(project_trades)
            submitted = month_add(start, rng.randint(1, max(2, month_diff(start, STATUS_PERIOD))))
            sub_date = f"{submitted}-{rng.randint(1, 28):02d}"
            status = rng.choices(["Approved", "Pending", "Rejected"], weights=[0.65, 0.25, 0.10])[0]
            approved_date = None
            if status == "Approved":
                y, m, d = map(int, sub_date.split("-"))
                lag = rng.randint(10, 75 if personality in ("change_heavy", "troubled") else 40)
                approved_date = date.fromordinal(date(y, m, d).toordinal() + lag).isoformat()
            rows["change_orders"].append(dict(
                co_id=f"CO-{co_counter:03d}", project_id=pid, description=tmpl.format(x=trade.lower() + " work"),
                reason=reason, trade=trade, status=status,
                amount=round(contract * rng.uniform(0.002, 0.018), -3),
                submitted_date=sub_date, approved_date=approved_date))
            co_counter += 1

    return rows


def write_csvs(rows: dict):
    DATA_DIR.mkdir(exist_ok=True)
    for table, data in rows.items():
        with open(DATA_DIR / f"{table}.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(data[0].keys()))
            writer.writeheader()
            writer.writerows(data)
        print(f"  {table:<17} {len(data):>5} rows")


if __name__ == "__main__":
    print(f"Generating data (status period {STATUS_PERIOD}) ...")
    write_csvs(generate())
    print(f"CSV files written to {DATA_DIR}")
