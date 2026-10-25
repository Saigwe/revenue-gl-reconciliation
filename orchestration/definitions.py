"""Dagster definitions: the bronze extract and every dbt model as software-defined assets.

- `bronze_ledger` regenerates the synthetic sub-ledger and GL.
- `revenue_recon_dbt` is one Dagster asset per dbt model; dbt tests run as asset checks.
- A daily schedule runs the whole graph, and a month-end job re-runs only the reconciliation
  reports so a late GL correction can be re-tied without reloading.

Run locally:
    pip install -r requirements-orchestration.txt
    dagster dev -m orchestration.definitions
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from dagster import (
    AssetExecutionContext,
    AssetKey,
    Definitions,
    ScheduleDefinition,
    asset,
    define_asset_job,
)
from dagster_dbt import DagsterDbtTranslator, DbtCliResource, DbtProject, dbt_assets

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = os.environ.get("RECON_DUCKDB_PATH", str(ROOT / "warehouse" / "recon.duckdb"))
os.environ["RECON_DUCKDB_PATH"] = DB_PATH

dbt_project = DbtProject(project_dir=ROOT / "dbt", profiles_dir=ROOT / "dbt")
dbt_project.prepare_if_dev()


class BronzeSourceTranslator(DagsterDbtTranslator):
    """Map every dbt source in `bronze` to the single `bronze_ledger` asset, so lineage connects."""

    def get_asset_key(self, dbt_resource_props):
        if dbt_resource_props["resource_type"] == "source":
            return AssetKey("bronze_ledger")
        return super().get_asset_key(dbt_resource_props)


@asset(group_name="bronze", description="Synthetic revenue sub-ledger, GL, FX and reference data.")
def bronze_ledger(context: AssetExecutionContext) -> None:
    cmd = [sys.executable, str(ROOT / "ingestion" / "generate_ledger.py"), "--db", DB_PATH]
    context.log.info(" ".join(cmd))
    subprocess.run(cmd, check=True)


@dbt_assets(manifest=dbt_project.manifest_path, dagster_dbt_translator=BronzeSourceTranslator())
def revenue_recon_dbt(context: AssetExecutionContext, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()


daily_job = define_asset_job("daily_ledger_refresh", selection="*")
month_end_job = define_asset_job(
    "month_end_retie",
    selection=["rpt_batch_reconciliation", "rpt_reconciliation_items", "rpt_monthly_reconciliation"],
)

defs = Definitions(
    assets=[bronze_ledger, revenue_recon_dbt],
    jobs=[daily_job, month_end_job],
    schedules=[
        ScheduleDefinition(job=daily_job, cron_schedule="0 6 * * *"),
        # 06:30 on days 1-3 of each month: the close window.
        ScheduleDefinition(job=month_end_job, cron_schedule="30 6 1-3 * *"),
    ],
    resources={"dbt": DbtCliResource(project_dir=dbt_project)},
)
