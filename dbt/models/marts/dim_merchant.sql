select merchant_id, merchant_name, country_code, currency_code, segment, has_subscription, onboarded_date
from {{ ref('stg_ref__merchants') }}
