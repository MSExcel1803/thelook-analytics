-- Guards the central revenue definition: cancelled and returned orders
-- must never contribute recognised revenue.
select order_id, order_status, net_revenue
from {{ ref('fct_orders') }}
where order_status in ('Cancelled', 'Returned')
  and net_revenue > 0
