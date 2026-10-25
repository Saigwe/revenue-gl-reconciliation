-- Reconciling items that explain each account-month variance (GL by posting month minus
-- sub-ledger by event month). Categories starting with 'unexplained_' need investigation.
with b as (
    select
        *,
        cast({{ dbt.date_trunc('month', 'gl_posting_date') }} as date) as gl_posting_month,
        case
            when is_late_arrival_batch and gl_posting_date = scheduled_posting_date then 'timing_late_arrival'
            else 'timing_late_posting'
        end as timing_category
    from {{ ref('rpt_batch_reconciliation') }}
),

posted as (
    select * from b
    where gl_journal_count > 0 and subledger_usd is not null
),

timing as (
    -- A batch posted in a different month from its events moves revenue between months.
    select batch_id, account_code, gl_posting_month as period_month, timing_category as category,
           subledger_usd as amount_usd
    from posted
    where gl_posting_month <> batch_month
    union all
    select batch_id, account_code, batch_month, timing_category, -subledger_usd
    from posted
    where gl_posting_month <> batch_month
),

primary_diff as (
    select batch_id, account_code, gl_posting_month as period_month,
           case when variance_reason = 'amount_mismatch' then 'unexplained_amount_mismatch'
                else 'gl_wrong_fx' end as category,
           gl_primary_usd - subledger_usd as amount_usd
    from posted
    where gl_primary_usd <> subledger_usd
),

duplicates as (
    select source_batch_id as batch_id, account_code, posting_month as period_month,
           'gl_duplicate' as category, amount_usd
    from {{ ref('fct_gl_revenue_journal') }}
    where is_duplicate_posting
),

missing as (
    select batch_id, account_code, batch_month as period_month,
           'unexplained_missing_in_gl' as category, -subledger_usd as amount_usd
    from b
    where variance_reason = 'missing_in_gl'
    union all
    select batch_id, account_code, gl_posting_month, 'unexplained_missing_in_subledger', gl_usd
    from b
    where variance_reason = 'missing_in_subledger'
)

select * from timing
union all select * from primary_diff
union all select * from duplicates
union all select * from missing
