-- One row per sub-ledger posting batch: what the GL should contain for that batch.
-- USD is translated at batch level (sum of local, then x rate, then round), matching the GL convention.
with batches as (
    select
        gl_batch_id,
        system_account_code     as account_code,
        currency_code,
        count(*)                as event_count,
        sum(amount_local)       as amount_local,
        min(loaded_at)          as first_loaded_at,
        max(loaded_at)          as last_loaded_at
    from {{ ref('fct_commission_revenue') }}
    group by 1, 2, 3
),

dated as (
    select
        *,
        {{ parse_yyyymmdd(dbt.split_part('gl_batch_id', "'-'", 2)) }} as batch_date,
        -- Late events post in an adjustment batch whose id carries the posting date: ...-ADJyyyymmdd
        case
            when gl_batch_id like '%-ADJ%'
            then {{ parse_yyyymmdd("replace(" ~ dbt.split_part('gl_batch_id', "'-'", 5) ~ ", 'ADJ', '')") }}
        end as adj_posting_date
    from batches
)

select
    d.gl_batch_id,
    d.account_code,
    d.currency_code,
    d.batch_date,
    cast({{ dbt.date_trunc('month', 'd.batch_date') }} as date)        as batch_month,
    coalesce(d.adj_posting_date, d.batch_date)                          as scheduled_posting_date,
    d.adj_posting_date is not null                                      as is_late_arrival_batch,
    d.event_count,
    d.amount_local,
    fx.usd_per_unit,
    {{ money('d.amount_local * fx.usd_per_unit') }}                     as expected_usd,
    d.first_loaded_at,
    d.last_loaded_at
from dated d
left join {{ ref('int_fx_rates_daily') }} fx
    on fx.rate_date = d.batch_date
    and fx.currency_code = d.currency_code
