/*
    The real tripwire under a derived boundary.

    A self-calibrating cutoff has one failure mode: a single genuinely-orphaned
    OLD order drags `complete_through` backwards across the entire warehouse,
    quietly marking months of good data "incomplete" and draining every revenue
    report. Nothing else would notice -- the models would still build, the
    tests would still pass, the numbers would just get smaller.

    So bound how far back the boundary is allowed to sit. Tripping this means
    either the generator has stalled or an old orphan has appeared; both need a
    human, and neither should be absorbed silently.
*/

with boundary as (

    select
        max(ordered_date)                                       as max_order_date,
        max(case when is_revenue_complete then ordered_date end) as complete_through
    from {{ ref('fct_orders') }}

)

select
    max_order_date,
    complete_through,
    date_diff(max_order_date, complete_through, day) as window_days

from boundary

where complete_through is null
   or date_diff(max_order_date, complete_through, day)
       > {{ var('max_completeness_window_days') }}
