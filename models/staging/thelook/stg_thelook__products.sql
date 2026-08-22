with source as (

    select * from {{ source('thelook', 'products') }}

),

renamed as (

    select
        -- ids
        id                                          as product_id,
        distribution_center_id                      as distribution_center_id,
        nullif(trim(sku), '')                       as sku,

        -- attributes
        nullif(trim(name), '')                      as product_name,
        nullif(trim(brand), '')                     as brand,
        nullif(trim(category), '')                  as category,
        nullif(trim(department), '')                as department,

        -- economics (catalogue list values, not what was actually transacted)
        round(cast(retail_price as numeric), 2)     as list_price,
        round(cast(cost as numeric), 2)             as list_cost,
        round(cast(retail_price - cost as numeric), 2)
                                                    as list_margin_amount,
        safe_divide(retail_price - cost, nullif(retail_price, 0))
                                                    as list_margin_pct

    from source

)

select * from renamed
