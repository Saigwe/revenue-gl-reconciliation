select
    journal_id,
    line_number,
    journal_id || '-' || cast(line_number as varchar)   as journal_line_id,
    cast(posting_date as date)                          as posting_date,
    account_code,
    currency_code,
    {{ money('amount_local') }}                         as amount_local,
    cast(fx_rate_used as decimal(18, 6))                as fx_rate_used,
    {{ money('amount_usd') }}                           as amount_usd,
    source_batch_id,
    description
from {{ source('bronze', 'gl_journal_lines') }}
