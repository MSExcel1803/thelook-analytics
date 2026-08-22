{{
    config(
        materialized = 'table',
        partition_by = {'field': 'revenue_date', 'data_type': 'date', 'granularity': 'month'}
    )
}}

/*
    Grain: one row per calendar day.

    Built on a date spine so days with zero orders appear as zero rather than
    silently disappearing — a gap that quietly breaks every time-series chart
    and every "vs. last week" comparison in the BI layer.
*/

with bounds as (

    select
        min(ordered_date) as start_date,
        max(ordered_date) as end_date
    from {{ ref('fct_orders') }}

),

completeness as (

    -- Inherit the boundary from fct_orders rather than recomputing it, so the
    -- two models can never disagree about which days are trustworthy.
    select max(ordered_date) as complete_through
    from {{ ref('fct_orders') }}
    where is_revenue_complete

),

spine as (

    select day as revenue_date
    from bounds,
    unnest(generate_date_array(bounds.start_date, bounds.end_date)) as day

),

daily as (

    select
        ordered_date                                    as revenue_date,
        count(*)                                        as orders_placed,
        countif(is_revenue_recognised)                  as orders,
        countif(is_cancelled)                           as cancelled_orders,
        countif(is_returned)                            as returned_orders,
        countif(is_first_purchase)                      as new_customer_orders,
        countif(is_repeat_purchase)                     as repeat_customer_orders,
        count(distinct user_id)                         as customers,
        sum(units_sold)                                 as units_sold,
        sum(net_revenue)                                as net_revenue,
        sum(net_cogs)                                   as net_cogs,
        sum(net_gross_profit)                           as net_gross_profit,
        sum(returned_revenue)                           as returned_revenue,
        sum(discount_amount)                            as discount_amount
    from {{ ref('fct_orders') }}
    group by ordered_date

),

final as (

    select
        s.revenue_date,
        s.revenue_date <= c.complete_through                as is_revenue_complete,
        date_trunc(s.revenue_date, week(monday))            as revenue_week,
        date_trunc(s.revenue_date, month)                   as revenue_month,
        date_trunc(s.revenue_date, quarter)                 as revenue_quarter,
        format_date('%A', s.revenue_date)                   as day_name,
        extract(dayofweek from s.revenue_date) in (1, 7)    as is_weekend,

        coalesce(d.orders_placed, 0)                        as orders_placed,
        coalesce(d.orders, 0)                               as orders,
        coalesce(d.cancelled_orders, 0)                     as cancelled_orders,
        coalesce(d.returned_orders, 0)                      as returned_orders,
        coalesce(d.new_customer_orders, 0)                  as new_customer_orders,
        coalesce(d.repeat_customer_orders, 0)               as repeat_customer_orders,
        coalesce(d.customers, 0)                            as customers,
        coalesce(d.units_sold, 0)                           as units_sold,
        coalesce(d.net_revenue, 0)                          as net_revenue,
        coalesce(d.net_cogs, 0)                             as net_cogs,
        coalesce(d.net_gross_profit, 0)                     as net_gross_profit,
        coalesce(d.returned_revenue, 0)                     as returned_revenue,
        coalesce(d.discount_amount, 0)                      as discount_amount,

        round(safe_divide(d.net_revenue, nullif(d.orders, 0)), 2)
                                                            as avg_order_value,
        round(safe_divide(d.net_gross_profit, nullif(d.net_revenue, 0)), 4)
                                                            as gross_margin_pct,
        round(safe_divide(d.cancelled_orders, nullif(d.orders_placed, 0)), 4)
                                                            as cancellation_rate,
        round(safe_divide(d.returned_orders, nullif(d.orders_placed, 0)), 4)
                                                            as return_rate,

        -- 7-day trailing smoothing, so the dashboard does not have to
        round(avg(coalesce(d.net_revenue, 0)) over (
            order by s.revenue_date rows between 6 preceding and current row
        ), 2)                                               as net_revenue_7d_avg,

        -- year-over-year comparison base
        lag(coalesce(d.net_revenue, 0), 364) over (order by s.revenue_date)
                                                            as net_revenue_ly

    from spine s
    left join daily d on s.revenue_date = d.revenue_date
    cross join completeness c

)

select * from final
