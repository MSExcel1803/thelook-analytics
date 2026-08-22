{{
    config(materialized = 'table')
}}

/*
    Grain: one row per acquisition cohort per month-offset.

    Cohort = month of first revenue-recognised order. Offset 0 is the
    acquisition month itself, so retention_rate at offset 0 is 1.0 by
    construction and should be excluded from retention charts.

    Uses a full cohort x period grid so a month where nobody from a cohort
    ordered shows as 0% retained rather than a missing point.
*/

with history as (

    select * from {{ ref('int_customer_order_history') }}
    where cohort_month is not null
      and is_revenue_recognised

),

cohort_sizes as (

    select
        cohort_month,
        count(distinct user_id) as cohort_customers
    from history
    where is_first_purchase
    group by cohort_month

),

max_period as (

    select
        cohort_month,
        max(months_since_first_purchase) as max_offset
    from history
    group by cohort_month

),

grid as (

    select
        cs.cohort_month,
        cs.cohort_customers,
        offset_month as months_since_first_purchase
    from cohort_sizes cs
    join max_period mp on cs.cohort_month = mp.cohort_month,
    unnest(generate_array(0, mp.max_offset)) as offset_month

),

activity as (

    select
        cohort_month,
        months_since_first_purchase,
        count(distinct user_id)     as active_customers,
        count(distinct order_id)    as orders,
        sum(net_revenue)            as net_revenue,
        sum(net_gross_profit)       as net_gross_profit
    from history
    group by 1, 2

),

final as (

    select
        g.cohort_month,
        g.months_since_first_purchase,
        g.cohort_customers,

        coalesce(a.active_customers, 0)                 as active_customers,
        coalesce(a.orders, 0)                           as orders,
        coalesce(a.net_revenue, 0)                      as net_revenue,
        coalesce(a.net_gross_profit, 0)                 as net_gross_profit,

        round(safe_divide(a.active_customers, g.cohort_customers), 4)
                                                        as retention_rate,
        round(safe_divide(a.net_revenue, g.cohort_customers), 2)
                                                        as revenue_per_cohort_customer,

        -- cumulative LTV curve: the number a growth team actually wants
        round(sum(coalesce(a.net_revenue, 0)) over (
            partition by g.cohort_month
            order by g.months_since_first_purchase
            rows between unbounded preceding and current row
        ) / g.cohort_customers, 2)                      as cumulative_ltv

    from grid g
    left join activity a
      on  g.cohort_month = a.cohort_month
      and g.months_since_first_purchase = a.months_since_first_purchase

)

select * from final
