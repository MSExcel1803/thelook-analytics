{{
    config(
        materialized = 'ephemeral'
    )
}}

/*
    Revenue-grain fact building block.

    Two decisions are encoded here and nowhere else:

    1. COGS uses the *inventory item's* landed cost, not the product catalogue
       cost. The catalogue cost is a current list value; the inventory cost is
       what was actually paid for the unit that shipped. Margin computed off the
       catalogue would drift for any product whose cost changed.

    2. Revenue is recognised only for items in `revenue_statuses`. Cancelled and
       Returned units contribute 0 to revenue and 0 to COGS, but are kept as
       rows so returns analysis stays possible.
*/

with order_items as (

    select * from {{ ref('stg_thelook__order_items') }}

),

inventory as (

    select * from {{ ref('stg_thelook__inventory_items') }}

),

products as (

    select * from {{ ref('stg_thelook__products') }}

),

joined as (

    select
        oi.order_item_id,
        oi.order_id,
        oi.user_id,
        oi.product_id,
        oi.inventory_item_id,
        oi.item_status,
        oi.is_revenue_recognised,
        oi.is_returned,
        oi.is_cancelled,
        oi.ordered_at,
        oi.ordered_date,
        oi.returned_at,

        p.product_name,
        p.brand,
        p.category,
        p.department,
        p.distribution_center_id,
        p.list_price,

        -- gross: what was billed, regardless of eventual status
        oi.sale_price                                       as gross_revenue,

        -- net: what we actually keep
        case when oi.is_revenue_recognised
             then oi.sale_price
             else cast(0 as numeric)
        end                                                 as net_revenue,

        case when oi.is_revenue_recognised
             then coalesce(inv.unit_cost, p.list_cost)
             else cast(0 as numeric)
        end                                                 as net_cogs,

        case when oi.is_returned then oi.sale_price
             else cast(0 as numeric)
        end                                                 as returned_revenue,

        cast(oi.is_revenue_recognised as int64)             as net_units,

        -- discount vs. catalogue price, a real analyst question
        round(p.list_price - oi.sale_price, 2)              as discount_amount

    from order_items oi
    left join inventory inv on oi.inventory_item_id = inv.inventory_item_id
    left join products  p   on oi.product_id        = p.product_id

),

final as (

    select
        *,
        net_revenue - net_cogs                              as net_gross_profit,
        safe_divide(net_revenue - net_cogs, nullif(net_revenue, 0))
                                                            as net_margin_pct
    from joined

)

select * from final
