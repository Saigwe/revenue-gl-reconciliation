# Design doc: Revenue-to-GL Reconciliation
*Keep it to about one page. Items marked `TODO` are filled from real decisions and measurements, never estimates.*

| | |
|---|---|
| **Author** | Stanley Igwe |
| **Status** | Draft |
| **Last updated** | 2026-10-25 |

## 1. Problem and users
- **Users:** revenue accountants, the controller, external auditors, finance data engineers.
- **Questions:**
  - Does each revenue account's GL balance agree with the sub-ledger for the month?
  - If not, why, and what entry fixes it?
  - Is any revenue sitting in the wrong account?
- **Pain (scenario):** the sub-ledger has ~100k events a month across currencies, while the GL gets summarised batches. Differences are found by hand in spreadsheets at close.

## 2. Requirements
| Type | Requirement |
|---|---|
| Functional | Tie every revenue account and month; classify every difference; propose reclass journals |
| Data quality | Journals balance; FX rate exists for every event date (fallback ≤ 5 days); no unexplained variance; planted errors always detected |
| Freshness / SLA | TODO, e.g. reconciliation ready by 08:00 on close days 1–3 |
| Scale | 91k events in 6 months today. Design for 10M events a month (the incremental fact and batch-level aggregation keep the reports small). |
| Audit | Reproducible from raw data with one command; every number traceable from account to batch to event |

## 3. Design
- **Reconcile at batch grain, report at month grain.** The sub-ledger's batch id is the join key to the GL, so a difference points straight at one journal. Month totals are then built from batch-level reconciling items, so the monthly view always adds up.
- **Translate where the GL translates.** USD = round(sum of local amounts × rate on the batch date). Converting event by event and summing would create rounding noise that hides real errors.
- **Incremental on load time, not event time.** `fct_commission_revenue` re-reads events with `loaded_at` later than the newest load minus `lookback_days`. A late event dated last month is still picked up. `check_incremental.py` proves the result equals a full refresh.
- **FX fallback rule:** use the latest rate published within 5 days. A null rate is better than a silent guess, so a `not_null` test stops the build.
- **Misclassification is separate from reconciliation.** The GL can tie to the sub-ledger and still be wrong, because both carry the account the upstream system assigned. A mapping from revenue type to the expected account finds those events, and `rpt_reclass_proposals` turns them into journals.

## 4. Options considered
| Decision | Options | Chosen | Why |
|---|---|---|---|
| Recon key | Date × account / batch id | Batch id | Points to one journal; date matching breaks on late postings |
| Incremental strategy | append / merge / delete+insert | delete+insert on `event_id` | Idempotent re-runs within the lookback; supported on DuckDB and Snowflake |
| Orchestration | Airflow / Dagster / cron | Dagster | Asset lineage matches dbt models; asset checks; partitions for monthly backfills |
| Test strategy | Assertions only / answer key | Answer key + assertions | Proves detection works, not just that the output looks valid |

## 5. Risks and what I'd change at 10× scale
- **Batch id parsing:** posting dates are read from the batch id. In production, take them from a batch header table instead.
- **Reasons are exclusive:** a batch with two problems gets only the first reason. TODO: add a reasons array, or a model with one row per issue.
- **10× scale:**
  - cluster the event fact by event month
  - move the reconciliation reports to incremental by month
  - add Dagster monthly partitions, so a single month re-ties without a full rebuild
