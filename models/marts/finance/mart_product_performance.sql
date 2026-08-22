{{
    config(materialized = 'table')
}}

/*
    Grain: one row per product per month.
    Answers "what is actually making money", not just "what is selling".
*/

with items as (

    select * from {{ ref('fct_order_items') }}

),

monthly as (

    select
        date_trunc(ordered_date, month)                 as revenue_month,
        product_id,

        count(*)                                        as line_items,
        sum(net_units)                                  as units_sold,
        countif(is_returned)                            as units_returned,
        count(distinct user_id)                         as customers,

        sum(net_revenue)                                as net_revenue,
        sum(net_cogs)                                   as net_cogs,
        sum(net_gross_profit)                           as net_gross_profit,
        sum(discount_amount)                            as discount_amount

    from items
    group by 1, 2

),

final as (

    select
        m.revenue_month,
        m.product_id,
        p.sku,
        p.product_name,
        p.brand,
        p.category,
        p.department,
        p.price_tier,
        p.distribution_center_name,

        m.line_items,
        m.units_sold,
        m.units_returned,
        m.customers,
        m.net_revenue,
        m.net_cogs,
        m.net_gross_profit,
        m.discount_amount,

        round(safe_divide(m.net_gross_profit, nullif(m.net_revenue, 0)), 4)
                                                        as gross_margin_pct,
        round(safe_divide(m.units_returned, nullif(m.line_items, 0)), 4)
                                                        as return_rate,
        round(safe_divide(m.net_revenue, nullif(m.units_sold, 0)), 2)
                                                        as avg_selling_price,

        -- rank within category for that month
        row_number() over (
            partition by m.revenue_month, p.category
            order by m.net_revenue desc
        )                                               as revenue_rank_in_category,

        -- share of the month's total revenue
        round(safe_divide(
            m.net_revenue,
            sum(m.net_revenue) over (partition by m.revenue_month)
        ), 6)                                           as pct_of_month_revenue

    from monthly m
    left join {{ ref('dim_products') }} p on m.product_id = p.product_id

)

select * from final
