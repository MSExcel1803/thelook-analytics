-- A customer cannot buy before they exist.
select
    user_id,
    registered_date,
    first_order_date
from {{ ref('dim_customers') }}
where first_order_date is not null
  and first_order_date < registered_date
