-- The audit claim: after reconciling items, every account-month ties to the GL with $0 unexplained.
select *
from {{ ref('rpt_monthly_reconciliation') }}
where recon_status <> 'tied'
