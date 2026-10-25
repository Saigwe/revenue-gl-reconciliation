-- Proposed reclassification journals: revenue booked to the wrong account, by month.
-- Each row moves amount_usd out of from_account_code into to_account_code.
select
    event_month,
    system_account_code                 as from_account_code,
    expected_account_code               as to_account_code,
    revenue_type,
    count(*)                            as event_count,
    count(distinct merchant_id)         as merchant_count,
    min(event_date)                     as first_event_date,
    max(event_date)                     as last_event_date,
    {{ money('sum(amount_usd)') }}      as amount_usd
from {{ ref('fct_commission_revenue') }}
where is_misclassified
group by 1, 2, 3, 4
