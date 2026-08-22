/*
    Reconciliation test: order-grain revenue must equal the sum of its
    line items. This is the test that catches a fan-out bug in a join,
    which is the single most common way an analytics pipeline silently
    starts reporting inflated revenue.

    Returns rows only on failure.
*/

with order_level as (

    select order_id, net_revenue
    from {{ ref('fct_orders') }}

),

item_level as (

    select order_id, sum(net_revenue) as net_revenue
    from {{ ref('fct_order_items') }}
    group by order_id

)

select
    o.order_id,
    o.net_revenue      as order_revenue,
    i.net_revenue      as line_item_revenue,
    abs(o.net_revenue - i.net_revenue) as difference
from order_level o
join item_level i using (order_id)
where abs(o.net_revenue - i.net_revenue) > 0.01
