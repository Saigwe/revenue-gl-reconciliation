-- Sub-ledger batch vs GL, one row per batch. variance_reason is checked in priority order.
{% set tol = var('tolerance') %}
with sl as (
    select * from {{ ref('fct_subledger_batch') }}
),

gl as (
    select
        source_batch_id,
        max(account_code)                                               as account_code,
        max(currency_code)                                              as currency_code,
        count(*)                                                        as journal_count,
        min(case when posting_seq = 1 then posting_date end)            as primary_posting_date,
        sum(case when posting_seq = 1 then amount_local end)            as primary_local,
        sum(case when posting_seq = 1 then amount_usd end)              as primary_usd,
        max(case when posting_seq = 1 then fx_rate_used end)            as primary_fx_rate,
        sum(amount_local)                                               as gl_local,
        sum(amount_usd)                                                 as gl_usd
    from {{ ref('fct_gl_revenue_journal') }}
    group by 1
)

select
    coalesce(sl.gl_batch_id, gl.source_batch_id)            as batch_id,
    coalesce(sl.account_code, gl.account_code)             as account_code,
    coalesce(sl.currency_code, gl.currency_code)           as currency_code,
    sl.batch_date,
    sl.batch_month,
    sl.scheduled_posting_date,
    gl.primary_posting_date                                 as gl_posting_date,
    coalesce(sl.is_late_arrival_batch, false)               as is_late_arrival_batch,
    sl.event_count,
    coalesce(gl.journal_count, 0)                           as gl_journal_count,
    sl.amount_local                                         as subledger_local,
    sl.expected_usd                                         as subledger_usd,
    sl.usd_per_unit                                         as expected_fx_rate,
    gl.primary_fx_rate                                      as gl_fx_rate,
    gl.gl_local,
    gl.gl_usd,
    gl.primary_usd                                          as gl_primary_usd,
    coalesce(gl.gl_local, 0) - coalesce(sl.amount_local, 0) as variance_local,
    coalesce(gl.gl_usd, 0) - coalesce(sl.expected_usd, 0)   as variance_usd,
    case
        when gl.source_batch_id is null then 'missing_in_gl'
        when sl.gl_batch_id is null then 'missing_in_subledger'
        when gl.journal_count > 1 then 'gl_duplicate'
        when abs(gl.primary_local - sl.amount_local) >= {{ tol }} then 'amount_mismatch'
        when abs(gl.primary_usd - sl.expected_usd) >= {{ tol }} then 'gl_wrong_fx'
        when gl.primary_posting_date <> sl.scheduled_posting_date then 'gl_late_posting'
        else 'tied'
    end                                                     as variance_reason
from sl
full outer join gl
    on gl.source_batch_id = sl.gl_batch_id
