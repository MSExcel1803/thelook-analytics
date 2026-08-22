-- Every cohort must be 100% retained in its own acquisition month.
-- If this fails, cohort assignment is wrong.
select cohort_month, retention_rate
from {{ ref('mart_customer_cohorts') }}
where months_since_first_purchase = 0
  and retention_rate < 0.9999
