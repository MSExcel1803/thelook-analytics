with source as (

    select * from {{ source('thelook', 'distribution_centers') }}

),

renamed as (

    select
        id                                          as distribution_center_id,
        nullif(trim(name), '')                      as distribution_center_name,
        latitude                                    as latitude,
        longitude                                   as longitude
    from source

)

select * from renamed
