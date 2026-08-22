{{
    config(
        materialized = 'ephemeral'
    )
}}

/*
    Per-customer order sequencing. Cohort membership is defined by the first
    *revenue-recognised* order, not the first order attempt and not the
    registration date — a customer who registered and only ever cancelled has
    never actually bought anything and does not belong to a purchase cohort.
*/

with orders as (

    select * from {{ ref('stg_thelook__orders') }}

),

order_economics as (

    select * from {{ ref('int_orders_aggregated') }}

),

joined as (

    select
        o.order_id,
        o.user_id,
        o.order_status,
        o.is_revenue_recognised,
        o.is_returned,
        o.is_cancelled,
        o.ordered_at,
        o.ordered_date,
        o.ordered_month,
        oe.net_revenue,
        oe.net_gross_profit,
        oe.units_sold
    from orders o
    left join order_economics oe on o.order_id = oe.order_id

),

sequenced as (

    select
        *,

        -- sequence over *all* orders
        row_number() over (
            partition by user_id order by ordered_at, order_id
        )                                                   as order_seq,

        -- sequence over purchases that actually counted
        case when is_revenue_recognised then
            row_number() over (
                partition by user_id, is_revenue_recognised
                order by ordered_at, order_id
            )
        end                                                 as purchase_seq,

        min(case when is_revenue_recognised then ordered_at end) over (
            partition by user_id
        )                                                   as first_purchase_at,

        max(case when is_revenue_recognised then ordered_at end) over (
            partition by user_id
        )                                                   as latest_purchase_at

    from joined

),

final as (

    select
        *,
        purchase_seq = 1                                    as is_first_purchase,
        purchase_seq > 1                                    as is_repeat_purchase,
        date_trunc(date(first_purchase_at), month)          as cohort_month,
        date_diff(
            date_trunc(ordered_date, month),
            date_trunc(date(first_purchase_at), month),
            month
        )                                                   as months_since_first_purchase
    from sequenced

)

select * from final
