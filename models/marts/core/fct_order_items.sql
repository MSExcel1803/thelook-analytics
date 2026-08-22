{{
    config(
        materialized = 'table',
        partition_by = {'field': 'ordered_date', 'data_type': 'date', 'granularity': 'month'},
        cluster_by = ['category', 'item_status']
    )
}}

-- Grain: one row per physical unit sold.
select
    order_item_id,
    order_id,
    user_id,
    product_id,
    inventory_item_id,
    distribution_center_id,

    item_status,
    is_revenue_recognised,
    is_returned,
    is_cancelled,

    product_name,
    brand,
    category,
    department,

    list_price,
    gross_revenue,
    net_revenue,
    net_cogs,
    net_gross_profit,
    net_margin_pct,
    returned_revenue,
    discount_amount,
    net_units,

    ordered_at,
    ordered_date,
    returned_at

from {{ ref('int_order_items_enriched') }}
