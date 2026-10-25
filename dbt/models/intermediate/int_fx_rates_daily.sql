-- One rate per calendar day and currency. FX is published on business days only, so weekends and
-- holidays fall back to the latest rate published in the previous 5 days (the same rule the GL uses).
-- No rate within 5 days leaves usd_per_unit null, which fails a not_null test instead of guessing.
-- The calendar covers event dates (amounts translate at the event date), not GL posting dates.
with calendar as (
    select event_date as rate_date from {{ ref('stg_ledger__commission_events') }}
    union
    select rate_date from {{ ref('stg_fx__rates') }}
),

currencies as (
    select distinct currency_code from {{ ref('stg_ref__merchants') }}
),

candidates as (
    select
        c.rate_date,
        k.currency_code,
        r.rate_date     as published_rate_date,
        r.usd_per_unit,
        row_number() over (
            partition by c.rate_date, k.currency_code
            order by r.rate_date desc
        ) as rn
    from calendar c
    cross join currencies k
    left join {{ ref('stg_fx__rates') }} r
        on r.currency_code = k.currency_code
        and r.rate_date <= c.rate_date
        and r.rate_date >= {{ dbt.dateadd('day', -5, 'c.rate_date') }}
    where k.currency_code <> 'USD'
)

select
    rate_date,
    currency_code,
    usd_per_unit,
    published_rate_date,
    published_rate_date <> rate_date as is_fallback_rate
from candidates
where rn = 1

union all

select
    rate_date,
    'USD',
    cast(1 as decimal(18, 6)),
    rate_date,
    false
from calendar
