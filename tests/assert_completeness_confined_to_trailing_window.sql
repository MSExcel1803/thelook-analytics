/*
    INVARIANT REGRESSION GUARD.

    Every order old enough to be considered complete must have line items.

    Be honest about what this test is now: since fct_orders derives the
    boundary as "the day before the first gap", this cannot fail given the
    current model definition. It is a tautology *today*. It is kept because it
    stops a future edit -- someone reintroducing a fixed offset, or changing
    the derivation -- from silently breaking the invariant the whole
    completeness design rests on.

    The test that can actually catch live data problems is
    assert_completeness_window_is_sane.
*/

select
    order_id,
    ordered_date,
    order_status,
    items_ordered

from {{ ref('fct_orders') }}

where is_revenue_complete
  and not has_line_items
