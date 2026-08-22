{{
    config(
        materialized = 'table',
        cluster_by = ['country', 'customer_status']
    )
}}

/*
    Grain: one row per registered customer.

    Encodes the two definitions that otherwise get re-invented per dashboard:

      active       — placed a recognised order in the last {{ var('active_window_days') }} days
      lifetime_*   — cumulative over recognised orders only

    "Days ago" is measured against the latest order date in the warehouse, not
    CURRENT_DATE, so the numbers stay stable if the source stops loading.
*/

with users as (

    select * from {{ ref('stg_thelook__users') }}

),

orders as (

    select * from {{ ref('fct_orders') }}

),

warehouse_asof as (

    select max(ordered_date) as as_of_date from orders

),

customer_orders as (

    select
        user_id,

        count(*)                                            as lifetime_orders_placed,
        countif(is_revenue_recognised)                      as lifetime_orders,
        countif(is_cancelled)                               as lifetime_cancelled_orders,
        countif(is_returned)                                as lifetime_returned_orders,

        -- Recognised orders only, to match the documented definition of
        -- `lifetime_*` above. Summing across all orders divided all-order
        -- revenue by a recognised-order count -- two different grains.
        sum(case when is_revenue_recognised then net_revenue end)
                                                            as lifetime_net_revenue,
        sum(case when is_revenue_recognised then net_gross_profit end)
                                                            as lifetime_gross_profit,
        sum(case when is_revenue_recognised then units_sold end)
                                                            as lifetime_units,

        -- How much of this customer's history is still landing. Without it,
        -- SUM() skips the nulls and a customer whose revenue is *unknown*
        -- reads as one who earned exactly nothing.
        -- Two different things, deliberately counted separately:
        --   in the lag window  -> LTV may still GROW as line items land
        --   missing economics  -> LTV is currently UNKNOWN, not zero
        -- An order can be in the window and still have all its line items.
        countif(is_revenue_recognised and not is_revenue_complete)
                                                            as lifetime_incomplete_orders,
        countif(is_revenue_recognised and not has_line_items)
                                                            as lifetime_orders_missing_economics,

        min(case when is_revenue_recognised then ordered_date end) as first_order_date,
        max(case when is_revenue_recognised then ordered_date end) as latest_order_date,
        any_value(cohort_month)                             as cohort_month

    from orders
    group by user_id

),

final as (

    select
        -- keys
        u.user_id,

        -- identity (PII — restrict in the BI layer)
        u.first_name,
        u.last_name,
        u.email,

        -- demographics
        u.age,
        u.age_band,
        u.gender,

        -- geography
        u.city,
        u.state,
        u.postal_code,
        u.country,

        -- acquisition
        u.traffic_source,
        u.registered_date,
        co.cohort_month,

        -- lifetime value
        coalesce(co.lifetime_orders, 0)                     as lifetime_orders,
        coalesce(co.lifetime_orders_placed, 0)              as lifetime_orders_placed,
        coalesce(co.lifetime_cancelled_orders, 0)           as lifetime_cancelled_orders,
        coalesce(co.lifetime_returned_orders, 0)            as lifetime_returned_orders,
        coalesce(co.lifetime_units, 0)                      as lifetime_units,
        coalesce(co.lifetime_net_revenue, 0)                as lifetime_net_revenue,
        coalesce(co.lifetime_gross_profit, 0)               as lifetime_gross_profit,
        round(safe_divide(co.lifetime_net_revenue, nullif(co.lifetime_orders, 0)), 2)
                                                            as avg_order_value,

        -- completeness
        coalesce(co.lifetime_incomplete_orders, 0)          as lifetime_incomplete_orders,
        coalesce(co.lifetime_incomplete_orders, 0) > 0      as has_incomplete_orders,
        coalesce(co.lifetime_orders_missing_economics, 0)   as lifetime_orders_missing_economics,

        -- recency
        co.first_order_date,
        co.latest_order_date,
        date_diff(w.as_of_date, co.latest_order_date, day)  as days_since_last_order,
        date_diff(co.latest_order_date, co.first_order_date, day)
                                                            as customer_tenure_days,

        -- segmentation
        coalesce(co.lifetime_orders, 0) > 0                 as has_purchased,
        coalesce(co.lifetime_orders, 0) > 1                 as is_repeat_customer,
        date_diff(w.as_of_date, co.latest_order_date, day) <= {{ var('active_window_days') }}
                                                            as is_active,

        case
            when coalesce(co.lifetime_orders, 0) = 0 then 'Never purchased'
            when date_diff(w.as_of_date, co.latest_order_date, day) <= {{ var('active_window_days') }}
                 and co.lifetime_orders = 1                 then 'Active - new'
            when date_diff(w.as_of_date, co.latest_order_date, day) <= {{ var('active_window_days') }}
                                                            then 'Active - repeat'
            when date_diff(w.as_of_date, co.latest_order_date, day) <= 365
                                                            then 'Lapsing'
            else                                                 'Churned'
        end                                                 as customer_status,

        w.as_of_date                                        as as_of_date

    from users u
    left join customer_orders co on u.user_id = co.user_id
    cross join warehouse_asof w

)

select * from final
