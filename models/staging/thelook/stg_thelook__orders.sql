with source as (

    select * from {{ source('thelook', 'orders') }}

),

renamed as (

    select
        -- ids
        order_id                                    as order_id,
        user_id                                     as user_id,

        -- status
        status                                      as order_status,
        status in ('Complete', 'Shipped', 'Processing')
                                                    as is_revenue_recognised,
        status = 'Cancelled'                        as is_cancelled,
        status = 'Returned'                         as is_returned,

        -- measures
        cast(num_of_item as int64)                  as items_ordered,

        -- timestamps
        created_at                                  as ordered_at,
        date(created_at)                            as ordered_date,
        date_trunc(date(created_at), month)         as ordered_month,
        shipped_at                                  as shipped_at,
        delivered_at                                as delivered_at,
        returned_at                                 as returned_at,

        -- fulfilment durations (null when the milestone never happened)
        date_diff(date(shipped_at),   date(created_at), day) as days_to_ship,
        date_diff(date(delivered_at), date(shipped_at), day) as days_in_transit,
        date_diff(date(delivered_at), date(created_at), day) as days_to_deliver

    from source
    where created_at >= timestamp('{{ var("analysis_start_date") }}')
      -- the generator writes future-dated orders; exclude them from all analysis
      and created_at <= current_timestamp()

)

select * from renamed
