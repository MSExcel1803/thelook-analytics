{{
    config(materialized = 'table')
}}

/*
    Grain: one row per traffic source per registration month.
    Ties acquisition channel to downstream value, which is the only way to
    judge a channel — volume alone rewards whichever channel is cheapest.
*/

with customers as (

    select * from {{ ref('dim_customers') }}

),

final as (

    select
        date_trunc(registered_date, month)              as registration_month,
        traffic_source,

        count(*)                                        as customers_acquired,
        countif(has_purchased)                          as customers_who_purchased,
        countif(is_repeat_customer)                     as repeat_customers,
        countif(is_active)                              as still_active_customers,

        sum(lifetime_orders)                            as lifetime_orders,
        sum(lifetime_net_revenue)                       as lifetime_net_revenue,
        sum(lifetime_gross_profit)                      as lifetime_gross_profit,

        round(safe_divide(countif(has_purchased), count(*)), 4)
                                                        as conversion_rate,
        round(safe_divide(countif(is_repeat_customer), nullif(countif(has_purchased), 0)), 4)
                                                        as repeat_rate,
        round(safe_divide(sum(lifetime_net_revenue), count(*)), 2)
                                                        as revenue_per_acquired_customer,
        round(safe_divide(sum(lifetime_net_revenue), nullif(countif(has_purchased), 0)), 2)
                                                        as revenue_per_purchasing_customer,
        round(safe_divide(sum(lifetime_orders), nullif(countif(has_purchased), 0)), 2)
                                                        as orders_per_purchasing_customer

    from customers
    group by 1, 2

)

select * from final
