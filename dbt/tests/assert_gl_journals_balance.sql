-- Double entry: every GL journal nets to zero in local currency and in USD.
select journal_id, sum(amount_local) as net_local, sum(amount_usd) as net_usd
from {{ ref('stg_gl__journal_lines') }}
group by journal_id
having sum(amount_local) <> 0 or sum(amount_usd) <> 0
