/*
    THE PHANTOM-ORDER GUARD.

    Context (discovered 2026-09-07): thelook_ecommerce rewrites history. Days
    near the write point carry inflated order counts that settle later --
    a mart built 2026-08-24 recorded 1,733 orders on 2026-08-23, while the
    source queried on 2026-09-07 held 236 for that same day.

    `is_revenue_complete` asks only "did the line items arrive?". A day can
    answer yes and still carry several times its true volume. That is what
    `completeness_settling_days` backs off from -- and this test is what stops
    that constant from going quietly stale, the same way
    assert_completeness_window_is_sane guards the derived boundary.

    A day flagged complete whose volume is wildly off its own trailing 28-day
    average is either inflation leaking past the buffer (high side) or a
    partially-written day (low side). Both need a human.

    Trailing AVG rather than median because BigQuery's PERCENTILE_CONT analytic
    function does not accept a window frame.
*/

with daily as (

    select
        revenue_date,
        is_revenue_complete,
        orders_placed
    from {{ ref('fct_daily_revenue') }}

),

with_baseline as (

    select
        *,
        avg(orders_placed) over (
            order by revenue_date
            rows between 28 preceding and 1 preceding
        ) as trailing_avg_orders
    from daily

)

select
    revenue_date,
    orders_placed,
    round(trailing_avg_orders, 1) as trailing_avg_orders,
    round(safe_divide(orders_placed, trailing_avg_orders), 2) as ratio

from with_baseline

where is_revenue_complete
  -- ignore the warm-up window where the trailing average is not yet meaningful
  and trailing_avg_orders > 50
  and (
        orders_placed > trailing_avg_orders * {{ var('volume_anomaly_multiple') }}
     or orders_placed < trailing_avg_orders * {{ var('volume_anomaly_floor') }}
  )
