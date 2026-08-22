{{
    config(
        materialized = 'table',
        partition_by = {'field': 'ordered_date', 'data_type': 'date', 'granularity': 'month'},
        cluster_by = ['order_status', 'user_id']
    )
}}

-- Grain: one row per order.
with orders as (

    select * from {{ ref('stg_thelook__orders') }}

),

economics as (

    select * from {{ ref('int_orders_aggregated') }}

),

first_gap as (

    -- Earliest order date that still has an order with no line items.
    select min(o.ordered_date) as first_incomplete_date
    from orders o
    left join economics e on o.order_id = e.order_id
    where e.order_id is null

),

completeness as (

    /*
        The source writes order headers ahead of their order_items rows, so the
        newest slice of data always looks artificially small.

        The boundary is DERIVED, not configured. Earlier versions used a fixed
        `lag_days` offset from the max order date; observation across two days
        showed the lag drifting (3 days, then 4), which means any constant is
        wrong on some future run and has to be re-tuned by hand. Instead:
        everything strictly before the first gap is complete.

        Still anchored to the data rather than wall-clock time, so a stalled
        generator cannot silently move the goalposts.
    */
    select
        coalesce(
            date_sub(f.first_incomplete_date, interval 1 day),
            (select max(ordered_date) from orders)   -- no gaps at all
        ) as complete_through
    from first_gap f

),

history as (

    select
        order_id,
        order_seq,
        purchase_seq,
        is_first_purchase,
        is_repeat_purchase,
        cohort_month,
        months_since_first_purchase
    from {{ ref('int_customer_order_history') }}

),

final as (

    select
        -- keys
        o.order_id,
        o.user_id,

        -- status
        o.order_status,
        o.is_revenue_recognised,
        o.is_cancelled,
        o.is_returned,

        -- sequencing
        h.order_seq,
        h.purchase_seq,
        h.is_first_purchase,
        h.is_repeat_purchase,
        h.cohort_month,
        h.months_since_first_purchase,

        -- completeness
        e.order_id is not null as has_line_items,
        o.ordered_date <= c.complete_through as is_revenue_complete,

        -- volume
        o.items_ordered,
        e.line_items,
        e.units_sold,
        e.distinct_products,
        e.distinct_categories,

        -- economics
        e.gross_revenue,
        e.net_revenue,
        e.net_cogs,
        e.net_gross_profit,
        safe_divide(e.net_gross_profit, nullif(e.net_revenue, 0)) as net_margin_pct,
        e.returned_revenue,
        e.discount_amount,
        e.returned_items,
        e.cancelled_items,

        -- fulfilment
        o.days_to_ship,
        o.days_in_transit,
        o.days_to_deliver,

        -- timestamps
        o.ordered_at,
        o.ordered_date,
        o.ordered_month,
        o.shipped_at,
        o.delivered_at,
        o.returned_at

    from orders o
    left join economics e on o.order_id = e.order_id
    left join history   h on o.order_id = h.order_id
    cross join completeness c

)

select * from final
