-- thelook_ecommerce is generated data and emits future-dated rows.
-- Staging filters them; this asserts the filter is actually holding.
select order_id, ordered_at
from {{ ref('fct_orders') }}
where ordered_at > current_timestamp()
