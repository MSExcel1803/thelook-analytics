{{
    config(
        materialized = 'ephemeral'
    )
}}

/*
    Rolls the revenue grain up to the order grain so fct_orders never has to
    re-derive line-item economics.
*/

with items as (

    select * from {{ ref('int_order_items_enriched') }}

),

aggregated as (

    select
        order_id,

        count(*)                                as line_items,
        sum(net_units)                          as units_sold,
        count(distinct product_id)              as distinct_products,
        count(distinct category)                as distinct_categories,

        sum(gross_revenue)                      as gross_revenue,
        sum(net_revenue)                        as net_revenue,
        sum(net_cogs)                           as net_cogs,
        sum(net_gross_profit)                   as net_gross_profit,
        sum(returned_revenue)                   as returned_revenue,
        sum(discount_amount)                    as discount_amount,

        countif(is_returned)                    as returned_items,
        countif(is_cancelled)                   as cancelled_items,

        -- most valuable category on the order, for basket analysis
        any_value(category)                     as sample_category

    from items
    group by order_id

)

select * from aggregated
