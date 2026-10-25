select
    order_id,
    merchant_id,
    cast(order_ts as timestamp)     as order_ts,
    cast(order_ts as date)          as order_date,
    currency_code,
    {{ money('subtotal_local') }}   as subtotal_local
from {{ source('bronze', 'orders') }}
