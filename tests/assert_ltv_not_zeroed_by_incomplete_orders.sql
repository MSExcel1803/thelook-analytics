/*
    A customer whose every recognised order is missing its economics has an
    *unknown* lifetime value, not a zero one. If avg_order_value comes back as
    a real number for such a customer, an aggregation has swallowed a null --
    the bug that made `sum(net_revenue)` across all orders look harmless.

    Keyed on `lifetime_orders_missing_economics`, NOT on
    `lifetime_incomplete_orders`. Sitting inside the lag window says nothing
    about whether the line items arrived; conflating the two makes this test
    fire on ~1,700 customers whose AOV is perfectly correct.
*/

select
    user_id,
    lifetime_orders,
    lifetime_orders_missing_economics,
    lifetime_net_revenue,
    avg_order_value

from {{ ref('dim_customers') }}

where lifetime_orders > 0
  and lifetime_orders = lifetime_orders_missing_economics
  and avg_order_value is not null
