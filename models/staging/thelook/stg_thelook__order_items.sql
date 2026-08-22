with source as (

    select * from {{ source('thelook', 'order_items') }}

),

renamed as (

    select
        -- ids
        id                                          as order_item_id,
        order_id                                    as order_id,
        user_id                                     as user_id,
        product_id                                  as product_id,
        inventory_item_id                           as inventory_item_id,

        -- status
        status                                      as item_status,
        status in ({{ "'" ~ var('revenue_statuses') | join("', '") ~ "'" }})
                                                    as is_revenue_recognised,
        status = 'Returned'                         as is_returned,
        status = 'Cancelled'                        as is_cancelled,

        -- measures
        round(cast(sale_price as numeric), 2)       as sale_price,

        -- timestamps
        created_at                                  as ordered_at,
        date(created_at)                            as ordered_date,
        shipped_at                                  as shipped_at,
        delivered_at                                as delivered_at,
        returned_at                                 as returned_at

    from source
    where created_at >= timestamp('{{ var("analysis_start_date") }}')
      and created_at <= current_timestamp()

)

select * from renamed
