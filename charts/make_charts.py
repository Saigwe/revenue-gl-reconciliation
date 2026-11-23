"""README charts from the gold marts. Usage: python charts/make_charts.py [--db warehouse/recon.duckdb] [--out docs/charts]"""
import argparse
from pathlib import Path

import duckdb
import matplotlib.dates as mdates

import style as st

ROOT = Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser()
ap.add_argument("--db", default=str(ROOT / "warehouse" / "recon.duckdb"))
ap.add_argument("--out", default=str(ROOT / "docs" / "charts"))
a = ap.parse_args()
OUT = Path(a.out)
con = duckdb.connect(a.db, read_only=True)

m = con.execute("""select period_month, sum(abs(timing_usd)), sum(abs(duplicate_usd)), sum(abs(fx_error_usd)),
                          sum(abs(unexplained_usd)), sum(abs(variance_usd)), sum(abs(subledger_usd))
                   from gold.rpt_monthly_reconciliation group by 1 order by 1""").fetchall()
x = [r[0] for r in m]
f, ax = st.fig(8, 3.5)
bottom = [0.0] * len(m)
for i, (lab, col) in enumerate([("Timing (late batches)", st.S[0]), ("Duplicate GL posting", st.S[1]),
                                ("Wrong FX rate", st.S[3]), ("Unexplained", st.CRITICAL)]):
    v = [float(r[1 + i]) for r in m]
    ax.bar(x, v, width=20, bottom=bottom, color=col, label=lab, edgecolor=st.SURFACE, linewidth=1)
    bottom = [b + y for b, y in zip(bottom, v)]
ax.yaxis.set_major_formatter(st.FuncFormatter(lambda v, _: f"${v:,.0f}"))
ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %y"))
total = sum(float(r[6]) for r in m)
st.head(ax, "Every dollar of sub-ledger vs GL variance is explained",
        f"Absolute variance by cause and month, on ${total / 1e6:,.1f}M of commission revenue", legend=True)
st.save(f, OUT / "variance_by_cause.png")
print(f"wrote charts to {OUT}")
