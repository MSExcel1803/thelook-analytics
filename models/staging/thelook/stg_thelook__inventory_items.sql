with source as (

    select * from {{ source('thelook', 'inventory_items') }}

),

renamed as (

    select
        id                                          as inventory_item_id,
        product_id                                  as product_id,
        product_distribution_center_id              as distribution_center_id,

        -- the landed cost of this specific physical unit: the correct basis
        -- for COGS, since catalogue cost drifts from what was actually paid
        round(cast(cost as numeric), 2)             as unit_cost,

        created_at                                  as stocked_at,
        sold_at                                     as sold_at,
        sold_at is not null                         as is_sold,
        date_diff(date(sold_at), date(created_at), day)
                                                    as days_on_shelf

    from source

)

select * from renamed
