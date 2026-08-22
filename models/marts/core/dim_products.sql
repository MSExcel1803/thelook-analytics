{{
    config(
        materialized = 'table',
        cluster_by = ['department', 'category']
    )
}}

-- Grain: one row per product SKU.
with products as (

    select * from {{ ref('stg_thelook__products') }}

),

centers as (

    select * from {{ ref('stg_thelook__distribution_centers') }}

),

inventory as (

    select
        product_id,
        count(*)                                as units_stocked,
        countif(is_sold)                        as units_sold_all_time,
        round(avg(unit_cost), 2)                as avg_unit_cost,
        round(avg(case when is_sold then days_on_shelf end), 1)
                                                as avg_days_on_shelf
    from {{ ref('stg_thelook__inventory_items') }}
    group by product_id

),

final as (

    select
        p.product_id,
        p.sku,
        p.product_name,
        p.brand,
        p.category,
        p.department,

        p.distribution_center_id,
        dc.distribution_center_name,

        p.list_price,
        p.list_cost,
        p.list_margin_amount,
        p.list_margin_pct,

        i.avg_unit_cost,
        i.units_stocked,
        i.units_sold_all_time,
        i.avg_days_on_shelf,
        round(safe_divide(i.units_sold_all_time, nullif(i.units_stocked, 0)), 4)
                                                as sell_through_rate,

        case
            when p.list_price < 25  then 'Budget (<$25)'
            when p.list_price < 75  then 'Mid ($25-$75)'
            when p.list_price < 200 then 'Premium ($75-$200)'
            else                         'Luxury ($200+)'
        end                                     as price_tier

    from products p
    left join centers   dc on p.distribution_center_id = dc.distribution_center_id
    left join inventory i  on p.product_id = i.product_id

)

select * from final
