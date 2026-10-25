-- A refund can never give back more commission than was charged on the order.
select order_id, revenue_type, sum(amount_local) as net_local
from {{ ref('fct_commission_revenue') }}
where order_id is not null
group by order_id, revenue_type
having sum(amount_local) < 0
