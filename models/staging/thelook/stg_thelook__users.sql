with source as (

    select * from {{ source('thelook', 'users') }}

),

renamed as (

    select
        -- ids
        id                                          as user_id,

        -- attributes
        initcap(trim(first_name))                   as first_name,
        initcap(trim(last_name))                    as last_name,
        lower(trim(email))                          as email,
        cast(age as int64)                          as age,
        case
            when age <  25 then '18-24'
            when age <  35 then '25-34'
            when age <  45 then '35-44'
            when age <  55 then '45-54'
            when age <  65 then '55-64'
            else                '65+'
        end                                         as age_band,
        nullif(trim(gender), '')                    as gender,

        -- geography
        nullif(trim(city), '')                      as city,
        nullif(trim(state), '')                     as state,
        nullif(trim(postal_code), '')               as postal_code,
        nullif(trim(country), '')                   as country,
        latitude                                    as latitude,
        longitude                                   as longitude,

        -- acquisition
        nullif(trim(traffic_source), '')            as traffic_source,

        -- timestamps
        created_at                                  as registered_at,
        date(created_at)                            as registered_date

    from source
    where created_at >= timestamp('{{ var("analysis_start_date") }}')
      and created_at <= current_timestamp()

)

select * from renamed
