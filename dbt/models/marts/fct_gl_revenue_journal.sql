select
    journal_id,
    source_batch_id,
    posting_date,
    cast({{ dbt.date_trunc('month', 'posting_date') }} as date) as posting_month,
    account_code,
    currency_code,
    amount_local,
    fx_rate_used,
    amount_usd,
    posting_seq,
    posting_seq > 1 as is_duplicate_posting
from {{ ref('int_gl_revenue_journals') }}
