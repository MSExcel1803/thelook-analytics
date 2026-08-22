{{
    config(
        materialized='table'
    )
}}

-- ---------------------------------------------------------------------------
-- Time spine
--
-- MetricFlow requires a dense, gapless date table to anchor `metric_time`.
-- Without it, a month with zero orders silently disappears from a time series
-- instead of showing as zero -- which is the difference between "we sold
-- nothing in February" and "February doesn't exist".
--
-- Grain: one row per calendar day. Range runs from the project-wide
-- `analysis_start_date` to a fixed horizon well past the dataset's tail.
-- ---------------------------------------------------------------------------

with spine as (

    select
        date_day

    from unnest(
        generate_date_array(
            date('{{ var("analysis_start_date") }}'),
            date('2030-12-31'),
            interval 1 day
        )
    ) as date_day

)

select
    date_day,
    date_trunc(date_day, week)    as date_week,
    date_trunc(date_day, month)   as date_month,
    date_trunc(date_day, quarter) as date_quarter,
    date_trunc(date_day, year)    as date_year

from spine
