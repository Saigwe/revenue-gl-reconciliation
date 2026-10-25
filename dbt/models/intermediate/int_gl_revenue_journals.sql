-- Revenue-side GL lines (revenue and contra-revenue accounts), one row per journal.
-- A sub-ledger batch should post exactly once; later postings of the same batch are duplicates.
select
    l.journal_id,
    l.source_batch_id,
    l.posting_date,
    l.account_code,
    l.currency_code,
    l.amount_local,
    l.fx_rate_used,
    l.amount_usd,
    row_number() over (partition by l.source_batch_id order by l.journal_id) as posting_seq
from {{ ref('stg_gl__journal_lines') }} l
join {{ ref('stg_ref__chart_of_accounts') }} a
    on a.account_code = l.account_code
where a.is_revenue_account
