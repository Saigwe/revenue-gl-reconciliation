select
    merchant_id,
    merchant_name,
    country_code,
    currency_code,
    segment,
    has_subscription,
    cast(onboarded_date as date) as onboarded_date
from {{ source('bronze', 'ref_merchants') }}
