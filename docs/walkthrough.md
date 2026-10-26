# 3-minute walkthrough: Revenue-to-GL Reconciliation

A timed script for a Loom recording of about 3 minutes (screen plus camera bubble, 1080p). Say it in your own words; the lines are a guide, not a teleprompter.

**Open these tabs before you press record:** README, dbt/models, docs/design_doc.md, orchestration/, GitHub Actions.

| Time | On screen | What to say |
|---|---|---|
| 0:00–0:20 | Portfolio card, then the README title | Month-end means proving that a high-volume revenue sub-ledger agrees with the general ledger, and explaining every difference. This pipeline ties them with $0 unexplained variance on all 26 account-months and proposes the journals to fix what's wrong. |
| 0:20–0:45 | README intro and the Data section | It rebuilds, on synthetic data, the accounting analytics I did for a food-delivery marketplace, where I tied commission revenue to the ledger with zero variance for the external auditors. No employer data or code is used. |
| 0:45–1:10 | README architecture: sub-ledger → FX → incremental fact → reconciliations | Events land in an incremental fact keyed on load time, not event time, so late events are never missed. |
| 1:10–1:35 | The FX model and its unit tests | FX is translated at batch level, the way the GL does it, with a 5-day fallback for weekends and holidays. Unit tests cover the fallback. |
| 1:35–2:00 | The reconciling-items and reclass-proposal models | Every difference becomes a reconciling item with a reason, and revenue booked to the wrong account gets a proposed reclassification journal. |
| 2:00–2:30 | The answer-key test, then a green Actions run | I plant a duplicate journal, a wrong-FX posting, a late posting and a mapping bug. The build fails unless each one is found with the right reason and amount, and nothing else is flagged. |
| 2:30–2:45 | `docs/design_doc.md`, the options table | The decision I'd defend in an interview: Incremental on load time rather than event time. A script proves the incremental result equals a full refresh, including late-arriving events. |
| 2:45–3:00 | Back to the README top | For a finance team, that means one tied number per account and month, a fix list, and an audit trail reviewers can rerun. The repo, numbers and design doc are linked under the video. |

## Recording checklist
- Close email, chat and notifications. Zoom the browser to 125% so code is readable.
- Run `make fixture-all` once before recording, so CI-style output is fresh if you show it.
- Keep to one take per section; Loom lets you trim. Aim for 2:45 to 3:10.
- Show real numbers on screen as you say them; never estimate on camera.
- Say "synthetic" out loud wherever the README labels data as synthetic.

## After recording
1. Copy the Loom share link.
2. In `README.md`, replace the roadmap line with `- [x] [3-minute Loom walkthrough](<your Loom link>)` and add the link under the title.
3. Add the link to this project's card on saigwe.github.io.
