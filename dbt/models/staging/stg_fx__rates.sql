select
    cast(rate_date as date)                 as rate_date,
    currency_code,
    cast(usd_per_unit as decimal(18, 6))    as usd_per_unit,
    source
from {{ source('bronze', 'fx_rates') }}
