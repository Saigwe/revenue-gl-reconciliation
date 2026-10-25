{{
    config(
        materialized='incremental',
        unique_key='event_id',
        incremental_strategy='delete+insert',
        on_schema_change='fail'
    )
}}
-- One row per sub-ledger event, translated to USD at the event date's rate, with the account the
-- event SHOULD sit in. Incremental on load time, not event time, so late-arriving events are picked up.
with events as (
    select *
    from {{ ref('stg_ledger__commission_events') }}
    {% if is_incremental() %}
    where loaded_at > (
        select {{ dbt.dateadd('day', -1 * var('lookback_days'), 'max(loaded_at)') }} from {{ this }}
    )
    {% endif %}
)

select
    e.event_id,
    e.order_id,
    e.merchant_id,
    e.event_ts,
    e.event_date,
    cast({{ dbt.date_trunc('month', 'e.event_date') }} as date)      as event_month,
    e.loaded_at,
    e.event_type,
    e.revenue_type,
    e.currency_code,
    e.amount_local,
    fx.usd_per_unit,
    cast(e.amount_local * fx.usd_per_unit as decimal(18, 6))        as amount_usd,
    e.system_account_code,
    coa.account_code                                                as expected_account_code,
    e.system_account_code <> coa.account_code                       as is_misclassified,
    e.gl_batch_id
from events e
left join {{ ref('int_fx_rates_daily') }} fx
    on fx.rate_date = e.event_date
    and fx.currency_code = e.currency_code
left join {{ ref('stg_ref__chart_of_accounts') }} coa
    on coa.revenue_type = case when e.event_type = 'refund' then 'refund' else e.revenue_type end
