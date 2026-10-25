select
    account_code,
    account_name,
    account_type,
    revenue_type,
    account_type in ('revenue', 'contra_revenue') as is_revenue_account
from {{ source('bronze', 'ref_chart_of_accounts') }}
