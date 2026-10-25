-- Answer-key test: every planted error is found with the right reason and amount,
-- and nothing else is flagged. The answer key is read here only, never by models.
with planted as (
    select * from {{ source('bronze', 'planted_issues') }}
),

gl_planted as (
    select * from planted where issue_type like 'gl_%'
),

batches as (
    select * from {{ ref('rpt_batch_reconciliation') }}
),

missed_or_wrong as (
    select p.issue_id, p.issue_type, 'not detected with the right reason' as problem
    from gl_planted p
    left join batches b on b.batch_id = p.source_batch_id
    where b.variance_reason is null or b.variance_reason <> p.issue_type
    union all
    select p.issue_id, p.issue_type, 'amount differs from answer key'
    from gl_planted p
    join batches b on b.batch_id = p.source_batch_id
    where p.issue_type in ('gl_duplicate', 'gl_wrong_fx')
      and abs(b.variance_usd - p.effect_usd) >= 0.01
),

false_positives as (
    select null as issue_id, b.variance_reason as issue_type, 'flagged but not planted: ' || b.batch_id
    from batches b
    where b.variance_reason <> 'tied'
      and b.batch_id not in (select source_batch_id from gl_planted)
),

misclass_missed as (
    select p.issue_id, p.issue_type, 'misclassified event not flagged: ' || p.event_id
    from planted p
    left join {{ ref('fct_commission_revenue') }} f on f.event_id = p.event_id
    where p.issue_type = 'misclassification' and not coalesce(f.is_misclassified, false)
),

misclass_extra as (
    select null, 'misclassification', 'flagged but not planted: ' || f.event_id
    from {{ ref('fct_commission_revenue') }} f
    where f.is_misclassified
      and f.event_id not in (select event_id from planted where event_id is not null)
)

select * from missed_or_wrong
union all select * from false_positives
union all select * from misclass_missed
union all select * from misclass_extra
