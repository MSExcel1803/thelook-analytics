with source as (

    select * from {{ source('thelook', 'events') }}

),

renamed as (

    select
        id                                          as event_id,
        user_id                                     as user_id,
        session_id                                  as session_id,
        cast(sequence_number as int64)              as sequence_number,

        nullif(trim(event_type), '')                as event_type,
        nullif(trim(traffic_source), '')            as traffic_source,
        nullif(trim(browser), '')                   as browser,
        nullif(trim(uri), '')                       as page_uri,

        nullif(trim(city), '')                      as city,
        nullif(trim(state), '')                     as state,
        nullif(trim(postal_code), '')               as postal_code,

        created_at                                  as occurred_at,
        date(created_at)                            as occurred_date

    from source
    where created_at >= timestamp('{{ var("analysis_start_date") }}')
      and created_at <= current_timestamp()

)

select * from renamed
