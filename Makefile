PY ?= python
DB ?= warehouse/recon.duckdb
FIXTURE_DB ?= warehouse/fixture.duckdb
DBT = cd dbt && RECON_DUCKDB_PATH=../$(DB) dbt

.PHONY: all fixture-all bronze bronze-fixture dbt incremental-check dagster clean

all: bronze dbt incremental-check                     ## full synthetic ledger (2,000 merchants, 6 months)
fixture-all:                                          ## small ledger, used in CI
	$(MAKE) bronze-fixture dbt incremental-check DB=$(FIXTURE_DB)

bronze:
	$(PY) ingestion/generate_ledger.py --db $(DB)

bronze-fixture:
	$(PY) ingestion/generate_ledger.py --db $(DB) --merchants 60 --end 2025-03-31 --orders-per-day 40

dbt:
	$(DBT) build --profiles-dir .

incremental-check:
	$(PY) scripts/check_incremental.py --db $(DB) --cutoff "2025-02-15 00:00:00"

dagster:
	RECON_DUCKDB_PATH=$(CURDIR)/$(DB) dagster dev -m orchestration.definitions

clean:
	rm -rf warehouse dbt/target dbt/logs
