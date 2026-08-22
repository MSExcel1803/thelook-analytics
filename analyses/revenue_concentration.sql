/*
    Ad-hoc analysis, not a model. `dbt compile` renders it to target/ so you can
    paste runnable SQL into the BigQuery console.

    Question: how concentrated is revenue? If the top 10% of customers drive
    most of it, retention work beats acquisition work.
*/

with customer_revenue as (

    select
        user_id,
        lifetime_net_revenue
    from {{ ref('dim_customers') }}
    where has_purchased

),

deciled as (

    select
        user_id,
        lifetime_net_revenue,
        ntile(10) over (order by lifetime_net_revenue desc) as revenue_decile
    from customer_revenue

)

select
    revenue_decile,
    count(*)                                    as customers,
    round(sum(lifetime_net_revenue), 2)         as revenue,
    round(safe_divide(
        sum(lifetime_net_revenue),
        sum(sum(lifetime_net_revenue)) over ()
    ), 4)                                       as pct_of_total_revenue,
    round(avg(lifetime_net_revenue), 2)         as avg_ltv
from deciled
group by revenue_decile
order by revenue_decile
