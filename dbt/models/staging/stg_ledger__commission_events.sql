select
    event_id,
    order_id,
    merchant_id,
    cast(event_ts as timestamp)                 as event_ts,
    cast(event_ts as date)                      as event_date,
    cast(loaded_at as timestamp)                as loaded_at,
    event_type,
    revenue_type,
    currency_code,
    {{ money('amount_local') }}                 as amount_local,
    account_code                                as system_account_code,
    gl_batch_id
from {{ source('bronze', 'commission_events') }}
-- Simulates what had landed by a given load time (see `make incremental-check`).
where loaded_at <= cast('{{ var("load_cutoff") }}' as timestamp)
