-- Month-end view per revenue account: sub-ledger vs GL, the reconciling items, and what is left.
-- 'tied' = no unexplained variance and the items fully explain the difference.
{% set tol = var('tolerance') %}
with sl as (
    select account_code, batch_month as period_month, sum(expected_usd) as subledger_usd
    from {{ ref('fct_subledger_batch') }}
    group by 1, 2
),

gl as (
    select account_code, posting_month as period_month, sum(amount_usd) as gl_usd
    from {{ ref('fct_gl_revenue_journal') }}
    group by 1, 2
),

items as (
    select
        account_code,
        period_month,
        sum(case when category like 'timing_%' then amount_usd else 0 end)         as timing_usd,
        sum(case when category = 'gl_duplicate' then amount_usd else 0 end)        as duplicate_usd,
        sum(case when category = 'gl_wrong_fx' then amount_usd else 0 end)         as fx_error_usd,
        sum(case when category like 'unexplained_%' then amount_usd else 0 end)    as unexplained_usd,
        sum(amount_usd)                                                             as items_usd
    from {{ ref('rpt_reconciliation_items') }}
    group by 1, 2
),

joined as (
    select
        coalesce(sl.account_code, gl.account_code)      as account_code,
        coalesce(sl.period_month, gl.period_month)      as period_month,
        coalesce(sl.subledger_usd, 0)                   as subledger_usd,
        coalesce(gl.gl_usd, 0)                          as gl_usd
    from sl
    full outer join gl
        on gl.account_code = sl.account_code
        and gl.period_month = sl.period_month
)

select
    j.account_code,
    a.account_name,
    j.period_month,
    j.subledger_usd,
    j.gl_usd,
    j.gl_usd - j.subledger_usd                                              as variance_usd,
    coalesce(i.timing_usd, 0)                                               as timing_usd,
    coalesce(i.duplicate_usd, 0)                                            as duplicate_usd,
    coalesce(i.fx_error_usd, 0)                                             as fx_error_usd,
    coalesce(i.unexplained_usd, 0)                                          as unexplained_usd,
    (j.gl_usd - j.subledger_usd) - coalesce(i.items_usd, 0)                 as residual_usd,
    -- GL after reversing known errors (duplicate and wrong-FX postings)
    j.gl_usd - coalesce(i.duplicate_usd, 0) - coalesce(i.fx_error_usd, 0)   as gl_corrected_usd,
    case
        when abs(coalesce(i.unexplained_usd, 0)) < {{ tol }}
         and abs((j.gl_usd - j.subledger_usd) - coalesce(i.items_usd, 0)) < {{ tol }}
        then 'tied'
        else 'investigate'
    end                                                                     as recon_status
from joined j
left join items i
    on i.account_code = j.account_code
    and i.period_month = j.period_month
left join {{ ref('dim_account') }} a
    on a.account_code = j.account_code
