select account_code, account_name, account_type, revenue_type, is_revenue_account
from {{ ref('stg_ref__chart_of_accounts') }}
