/*
    Guards the inverse: an order flagged incomplete must not have been silently
    coalesced to zero revenue somewhere downstream. Zero and "not yet known" are
    different numbers, and conflating them is how a warehouse starts
    understating the current week without anyone noticing.
*/

select
    order_id,
    ordered_date,
    net_revenue

from {{ ref('fct_orders') }}

where not has_line_items
  and net_revenue is not null
