"""Generate a synthetic marketplace revenue sub-ledger and general ledger (GL) into DuckDB `bronze`.

Modelled on a real problem (commission revenue tied to the GL for audit), but every row is
synthetic and produced from a fixed seed. Known errors are planted on purpose and written to
`bronze.planted_issues`, an answer key used ONLY by tests, never by models.

Planted issues
- misclassification : marketing-fee events for enterprise merchants booked to the commission
                      account during a date window (a mapping-rule bug upstream)
- gl_duplicate      : one GL journal posted twice
- gl_wrong_fx       : one GL journal translated at the previous month's rate
- gl_late_posting   : one month-end GL journal posted two days late (cut-off item)
- late arrival      : ~0.5% of sub-ledger events load 5-12 days after they happen (natural, not an error)

Usage
    python ingestion/generate_ledger.py --db warehouse/recon.duckdb
    python ingestion/generate_ledger.py --db warehouse/recon.duckdb --merchants 60 --end 2025-03-31 --orders-per-day 40
"""
from __future__ import annotations

import argparse
import datetime as dt
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd

CURRENCIES = {"US": "USD", "CA": "CAD", "AU": "AUD", "DE": "EUR", "NZ": "NZD"}
COUNTRY_WEIGHTS = [0.55, 0.15, 0.12, 0.10, 0.08]
FX_START = {"CAD": 0.73, "AUD": 0.66, "EUR": 1.08, "NZD": 0.60}
FX_HOLIDAYS = {dt.date(2025, 1, 1), dt.date(2025, 4, 18), dt.date(2025, 4, 21), dt.date(2025, 12, 25)}
SEGMENTS = ["smb", "mid_market", "enterprise"]
SEGMENT_WEIGHTS = [0.70, 0.22, 0.08]
SEGMENT_TAKE_RATE = {"smb": 0.25, "mid_market": 0.20, "enterprise": 0.15}

CHART_OF_ACCOUNTS = [
    ("1200", "Accounts receivable - merchants", "asset", None),
    ("4010", "Marketplace commission revenue", "revenue", "commission"),
    ("4020", "Merchant marketing fee revenue", "revenue", "marketing_fee"),
    ("4030", "Merchant subscription revenue", "revenue", "subscription"),
    ("4090", "Commission refunds and credits", "contra_revenue", "refund"),
]
REVENUE_TYPE_ACCOUNT = {"commission": "4010", "marketing_fee": "4020", "subscription": "4030"}
REFUND_ACCOUNT = "4090"

MISCLASS_WINDOW = (dt.date(2025, 2, 10), dt.date(2025, 3, 20))


def daterange(start: dt.date, end: dt.date):
    for i in range((end - start).days + 1):
        yield start + dt.timedelta(days=i)


def make_merchants(rng: np.random.Generator, n: int, start: dt.date) -> pd.DataFrame:
    countries = rng.choice(list(CURRENCIES), size=n, p=COUNTRY_WEIGHTS)
    segments = rng.choice(SEGMENTS, size=n, p=SEGMENT_WEIGHTS)
    onboarded = [start - dt.timedelta(days=int(d)) for d in rng.integers(0, 900, size=n)]
    return pd.DataFrame({
        "merchant_id": [f"M{i:05d}" for i in range(1, n + 1)],
        "merchant_name": [f"Merchant {i:05d}" for i in range(1, n + 1)],
        "country_code": countries,
        "currency_code": [CURRENCIES[c] for c in countries],
        "segment": segments,
        "has_subscription": rng.random(n) < 0.30,
        "onboarded_date": onboarded,
    })


def make_fx(rng: np.random.Generator, start: dt.date, end: dt.date) -> pd.DataFrame:
    """Business-day rates only (no weekends or holidays), so models must apply a fallback rule."""
    rows = []
    level = dict(FX_START)
    for d in daterange(start - dt.timedelta(days=10), end):
        for ccy in level:
            level[ccy] *= float(np.exp(rng.normal(0, 0.004)))
        if d.weekday() >= 5 or d in FX_HOLIDAYS:
            continue
        rows += [(d, ccy, round(rate, 6), "synthetic_ecb_style") for ccy, rate in level.items()]
    return pd.DataFrame(rows, columns=["rate_date", "currency_code", "usd_per_unit", "source"])


def fx_lookup(fx: pd.DataFrame):
    """Rate for a date = latest published rate on or before it (same rule the dbt model uses)."""
    table = {(r.currency_code, r.rate_date): r.usd_per_unit for r in fx.itertuples()}

    def rate(ccy: str, d: dt.date) -> float:
        if ccy == "USD":
            return 1.0
        for back in range(0, 6):
            hit = table.get((ccy, d - dt.timedelta(days=back)))
            if hit is not None:
                return hit
        raise ValueError(f"no rate for {ccy} near {d}")

    return rate


def make_events(rng, merchants: pd.DataFrame, start: dt.date, end: dt.date, orders_per_day: int):
    m = merchants.set_index("merchant_id")
    ids = merchants["merchant_id"].to_numpy()
    # Pareto-ish order share: a few merchants dominate, as in real marketplaces.
    weights = rng.pareto(1.5, size=len(ids)) + 1
    weights = weights / weights.sum()

    orders, events = [], []
    order_seq = event_seq = 0

    def add_event(order_id, merchant_id, ts, event_type, revenue_type, amount):
        nonlocal event_seq
        event_seq += 1
        lag_minutes = int(rng.integers(5, 240))
        loaded = ts + dt.timedelta(minutes=lag_minutes)
        if rng.random() < 0.005:  # late-arriving event
            loaded = ts + dt.timedelta(days=int(rng.integers(5, 13)))
        events.append({
            "event_id": f"E{event_seq:08d}", "order_id": order_id, "merchant_id": merchant_id,
            "event_ts": ts, "loaded_at": loaded, "event_type": event_type,
            "revenue_type": revenue_type, "currency_code": m.at[merchant_id, "currency_code"],
            "amount_local": round(float(amount), 2),
        })

    for d in daterange(start, end):
        n = int(rng.poisson(orders_per_day * (1.15 if d.weekday() >= 4 else 1.0)))
        picks = rng.choice(ids, size=n, p=weights)
        for merchant_id in picks:
            order_seq += 1
            order_id = f"O{order_seq:08d}"
            ts = dt.datetime.combine(d, dt.time()) + dt.timedelta(seconds=int(rng.integers(0, 86400)))
            subtotal = round(float(rng.lognormal(3.3, 0.55)), 2)
            orders.append({"order_id": order_id, "merchant_id": merchant_id, "order_ts": ts,
                           "currency_code": m.at[merchant_id, "currency_code"], "subtotal_local": subtotal})
            take = SEGMENT_TAKE_RATE[m.at[merchant_id, "segment"]]
            add_event(order_id, merchant_id, ts, "charge", "commission", subtotal * take)
            if rng.random() < 0.10:
                add_event(order_id, merchant_id, ts, "charge", "marketing_fee", subtotal * 0.05)
            if rng.random() < 0.03:
                refund_ts = ts + dt.timedelta(days=int(rng.integers(0, 4)), minutes=int(rng.integers(1, 600)))
                if refund_ts.date() <= end:
                    add_event(order_id, merchant_id, refund_ts, "refund", "commission",
                              -subtotal * take * float(rng.uniform(0.3, 1.0)))
        if d.day == 1:
            for merchant_id in merchants.loc[merchants["has_subscription"], "merchant_id"]:
                ts = dt.datetime.combine(d, dt.time(2, 0))
                add_event(None, merchant_id, ts, "charge", "subscription", 49.0)

    return pd.DataFrame(orders), pd.DataFrame(events)


def assign_accounts(events: pd.DataFrame, merchants: pd.DataFrame) -> pd.DataFrame:
    """System-assigned GL account, including the planted mapping bug."""
    seg = events["merchant_id"].map(merchants.set_index("merchant_id")["segment"])
    acct = np.where(events["event_type"] == "refund", REFUND_ACCOUNT,
                    events["revenue_type"].map(REVENUE_TYPE_ACCOUNT))
    event_date = events["event_ts"].dt.date
    bug = ((events["revenue_type"] == "marketing_fee") & (seg == "enterprise")
           & (event_date >= MISCLASS_WINDOW[0]) & (event_date <= MISCLASS_WINDOW[1]))
    events = events.copy()
    events["account_code"] = np.where(bug, "4010", acct)
    events["_misclassified"] = bug
    return events


def build_gl(events: pd.DataFrame, rate) -> tuple[pd.DataFrame, pd.DataFrame]:
    """One GL journal per (batch date, currency, account). Late events post in an ADJ batch on the load date."""
    ev = events.copy()
    ev["event_date"] = ev["event_ts"].dt.date
    ev["is_late"] = (ev["loaded_at"].dt.date - ev["event_date"]).apply(lambda x: x.days) >= 5
    ev["posting_date"] = np.where(ev["is_late"], ev["loaded_at"].dt.date, ev["event_date"])
    ev["gl_batch_id"] = ("SL-" + pd.to_datetime(ev["event_date"]).dt.strftime("%Y%m%d") + "-"
                         + ev["currency_code"] + "-" + ev["account_code"]
                         + np.where(ev["is_late"], "-ADJ" + pd.to_datetime(ev["posting_date"]).dt.strftime("%Y%m%d"), ""))

    batches = (ev.groupby(["gl_batch_id", "event_date", "posting_date", "currency_code", "account_code"], as_index=False)
                 ["amount_local"].sum())
    batches["amount_local"] = batches["amount_local"].round(2)
    batches = batches.sort_values(["posting_date", "gl_batch_id"]).reset_index(drop=True)

    lines = []
    for i, b in enumerate(batches.itertuples(), start=1):
        fx = rate(b.currency_code, b.event_date)  # translate at the transaction date's rate
        usd = round(b.amount_local * fx, 2)
        jid = f"J{i:07d}"
        desc = f"Revenue sub-ledger batch {b.gl_batch_id}"
        lines.append((jid, 1, b.posting_date, b.account_code, b.currency_code, b.amount_local, fx, usd, b.gl_batch_id, desc))
        lines.append((jid, 2, b.posting_date, "1200", b.currency_code, -b.amount_local, fx, -usd, b.gl_batch_id, desc))
    gl = pd.DataFrame(lines, columns=["journal_id", "line_number", "posting_date", "account_code", "currency_code",
                                      "amount_local", "fx_rate_used", "amount_usd", "source_batch_id", "description"])
    return ev.drop(columns=["event_date", "is_late", "posting_date"]), gl


def plant_gl_issues(rng, gl: pd.DataFrame, rate) -> tuple[pd.DataFrame, list[dict]]:
    issues = []
    rev = gl[(gl["line_number"] == 1) & (gl["currency_code"] != "USD") & (~gl["source_batch_id"].str.contains("ADJ"))]

    # 1) duplicate journal
    dup_jid = rev.sample(1, random_state=int(rng.integers(1e9))).iloc[0]["journal_id"]
    dup = gl[gl["journal_id"] == dup_jid].copy()
    dup["journal_id"] = dup_jid + "D"
    gl = pd.concat([gl, dup], ignore_index=True)
    r = dup.iloc[0]
    issues.append({"issue_type": "gl_duplicate", "source_batch_id": r.source_batch_id, "event_id": None,
                   "account_code": r.account_code, "effect_usd": float(r.amount_usd)})

    # 2) wrong FX rate: previous month's rate
    cand = rev[rev["journal_id"] != dup_jid]
    r = cand.sample(1, random_state=int(rng.integers(1e9))).iloc[0]
    batch_date = dt.datetime.strptime(r.source_batch_id.split("-")[1], "%Y%m%d").date()
    wrong_fx = rate(r.currency_code, batch_date - dt.timedelta(days=31))
    mask = gl["journal_id"] == r.journal_id
    gl.loc[mask, "fx_rate_used"] = wrong_fx
    gl.loc[mask, "amount_usd"] = (gl.loc[mask, "amount_local"] * wrong_fx).round(2)
    new_usd = round(r.amount_local * wrong_fx, 2)
    issues.append({"issue_type": "gl_wrong_fx", "source_batch_id": r.source_batch_id, "event_id": None,
                   "account_code": r.account_code, "effect_usd": round(new_usd - float(r.amount_usd), 2)})

    # 3) late posting across a month end
    month_end = rev[pd.to_datetime(rev["posting_date"]).dt.is_month_end & ~rev["journal_id"].isin([dup_jid, r.journal_id])]
    if len(month_end):
        late = month_end.sample(1, random_state=int(rng.integers(1e9))).iloc[0]
        mask = gl["journal_id"] == late.journal_id
        gl.loc[mask, "posting_date"] = late.posting_date + dt.timedelta(days=2)
        issues.append({"issue_type": "gl_late_posting", "source_batch_id": late.source_batch_id, "event_id": None,
                       "account_code": late.account_code, "effect_usd": float(late.amount_usd)})
    return gl, issues


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default="warehouse/recon.duckdb")
    ap.add_argument("--merchants", type=int, default=2000)
    ap.add_argument("--start", type=dt.date.fromisoformat, default=dt.date(2025, 1, 1))
    ap.add_argument("--end", type=dt.date.fromisoformat, default=dt.date(2025, 6, 30))
    ap.add_argument("--orders-per-day", type=int, default=400)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)
    merchants = make_merchants(rng, args.merchants, args.start)
    fx = make_fx(rng, args.start, args.end)
    rate = fx_lookup(fx)
    orders, events = make_events(rng, merchants, args.start, args.end, args.orders_per_day)
    events = assign_accounts(events, merchants)
    events, gl = build_gl(events, rate)
    gl, issues = plant_gl_issues(rng, gl, rate)

    for ev in events[events["_misclassified"]].itertuples():
        issues.append({"issue_type": "misclassification", "source_batch_id": ev.gl_batch_id, "event_id": ev.event_id,
                       "account_code": ev.account_code, "effect_usd": None})
    events = events.drop(columns=["_misclassified"])
    planted = pd.DataFrame(issues)
    planted.insert(0, "issue_id", range(1, len(planted) + 1))

    coa = pd.DataFrame(CHART_OF_ACCOUNTS, columns=["account_code", "account_name", "account_type", "revenue_type"])
    tables = {"ref_merchants": merchants, "ref_chart_of_accounts": coa, "fx_rates": fx, "orders": orders,
              "commission_events": events, "gl_journal_lines": gl, "planted_issues": planted}

    Path(args.db).parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(args.db)
    con.execute("create schema if not exists bronze")
    for name, df in tables.items():
        con.register("df", df)
        con.execute(f"create or replace table bronze.{name} as select * from df")
        con.unregister("df")
        print(f"bronze.{name:<22} {len(df):>9,} rows")
    con.close()


if __name__ == "__main__":
    main()
