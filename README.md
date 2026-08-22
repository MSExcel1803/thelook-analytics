# theLook Ecommerce — Analytics Engineering Pipeline

A production-shaped analytics stack on **BigQuery + dbt**: raw public data
transformed into a tested, documented, version-controlled warehouse with a
**semantic layer** that defines every business metric exactly once, and **CI
that runs data quality tests on every pull request**.

| | |
|---|---|
| **Warehouse** | Google BigQuery |
| **Transformation** | dbt (Core or Cloud) |
| **Source** | `bigquery-public-data.thelook_ecommerce` — 7 tables, ~2M order items |
| **Layers** | sources → staging → intermediate → marts → semantic |
| **Testing** | schema tests + custom singular tests, run in CI |
| **BI** | Power BI / Tableau, connected to marts only |

---

## Why this project exists

Most portfolio "data pipelines" are a notebook that reads a CSV and draws a
chart. This one is built the way a data team actually builds: layered models,
enforced contracts between layers, explicit business-logic decisions written
down once, and automated tests that fail the build when the data breaks.

The three things here that portfolio projects usually skip:

1. **A semantic layer.** `net_revenue` is defined in exactly one place. Every
   dashboard, notebook and future agent resolves it identically. This is the
   whole reason semantic layers exist — five dashboards computing "revenue"
   five slightly different ways is the most common failure of a BI function.
2. **CI on the data layer.** Every PR spins a throwaway BigQuery dataset,
   builds all models, runs all tests, and tears the dataset down. A join that
   fans out and doubles revenue fails the build instead of reaching a VP's
   dashboard.
3. **Reconciliation tests, not just null checks.** `assert_order_revenue_ties_to_line_items`
   proves the order grain and the item grain agree to the cent.

---

## Architecture

```
bigquery-public-data.thelook_ecommerce   (sources + freshness checks)
                │
                ▼
    ┌──────────────────────────┐
    │  staging/  (views)       │  1:1 with sources. Rename, cast, dedupe,
    │  stg_thelook__*          │  null-handling, drop future-dated rows.
    └──────────────────────────┘  No business logic. No joins.
                │
                ▼
    ┌──────────────────────────┐
    │  intermediate/ (ephemeral)│ The joins and the hard decisions:
    │  int_*                    │ true COGS, revenue recognition,
    └──────────────────────────┘ cohort assignment, order sequencing.
                │
                ▼
    ┌──────────────────────────────────────────────────────┐
    │  marts/  (tables, partitioned + clustered)           │
    │                                                       │
    │  core/       fct_orders, fct_order_items,            │
    │              dim_customers, dim_products             │
    │  finance/    fct_daily_revenue,                      │
    │              mart_product_performance                │
    │  marketing/  mart_customer_cohorts,                  │
    │              mart_acquisition_channels               │
    └──────────────────────────────────────────────────────┘
                │
                ▼
    ┌──────────────────────────┐
    │  semantic/  (MetricFlow) │  15 metrics defined once.
    └──────────────────────────┘
                │
                ▼
      Power BI / Tableau  (declared as dbt exposures)
```

---

## The decisions this warehouse encodes

An analytics engineer's real output is not SQL, it is *settled definitions*.
These are stated here so nobody downstream has to guess.

### Revenue

**Net revenue** counts units in status `Complete`, `Shipped` or `Processing`.
Cancelled and returned units contribute **zero** revenue and **zero** COGS —
but their rows are retained so return-rate analysis stays possible. Gross
revenue (everything billed) is kept alongside so the gap is measurable.

Set once in `dbt_project.yml` as `vars.revenue_statuses`; referenced by the
staging model, the `net_revenue()` macro, and the metrics layer.

### Cost of goods

COGS uses **`inventory_items.cost`** — the landed cost of the specific physical
unit that shipped — not `products.cost`, which is a current catalogue list
value. Using the catalogue cost silently misstates margin for any product whose
cost has moved since it was stocked.

### Cohort membership

A customer's cohort is the month of their **first revenue-recognised order**,
not their registration month and not their first order attempt. Someone who
registered and only ever cancelled has never bought anything and belongs to no
purchase cohort.

### Active customer

A recognised order within the trailing **90 days** (`vars.active_window_days`),
measured against **the latest order date in the warehouse**, not
`CURRENT_DATE`. If the source stops loading, every customer would otherwise
drift into "churned" overnight — a real failure mode that makes a dashboard
lie without erroring.

### Grain discipline

- `fct_orders` — one row per order. Use for order counts, AOV, fulfilment.
- `fct_order_items` — one row per unit. Use for category/brand/product mix.

Counting orders off the item grain inflates them by the basket size. The
reconciliation test enforces that the two agree on revenue.

---

## Data quality

**128 automated tests** across three kinds:

**Schema tests** — `unique`, `not_null`, `accepted_values`, `relationships`
(true foreign-key enforcement, which BigQuery does not provide), and
`dbt_utils.accepted_range` on every rate, percentage and monetary column.

**Composite-key tests** — `dbt_utils.unique_combination_of_columns` on the
grain of each aggregate mart, so a grain violation fails loudly.

**Singular tests** — the business-logic assertions:

| Test | What it protects against |
|---|---|
| `assert_order_revenue_ties_to_line_items` | Join fan-out inflating revenue |
| `assert_cancelled_orders_have_zero_revenue` | Revenue definition drifting |
| `assert_cohort_starts_at_full_retention` | Broken cohort assignment |
| `assert_first_order_not_before_registration` | Timestamp/timezone corruption |
| `assert_no_future_dated_orders` | Generated future rows leaking into metrics |

Plus **source freshness** checks so a stalled load is visible before it shows
up as a suspicious dip in a chart.

---

## Quickstart

```bash
# 1. Install
pip install dbt-bigquery
dbt deps

# 2. Configure (dbt Core)
cp profiles.yml.example ~/.dbt/profiles.yml   # then fill in project + keyfile

# 3. Verify the connection
dbt debug

# 4. Build everything and run every test
dbt build

# 5. Browse the lineage graph and docs
dbt docs generate && dbt docs serve
```

Useful selectors:

```bash
dbt build --select staging              # just the staging layer
dbt build --select +dim_customers       # dim_customers and everything upstream
dbt build --select marts.finance        # one mart folder
dbt test --select source:thelook        # source-level contracts only
dbt build --select +exposure:executive_revenue_overview   # what one dashboard needs
```

Querying the semantic layer (dbt Cloud / MetricFlow):

```bash
dbt sl query --metrics net_revenue,average_order_value --group-by metric_time__month
dbt sl query --metrics repeat_purchase_rate --group-by customer__traffic_source
```

---

## Repository layout

```
├── dbt_project.yml              Project config, layer materialisations, business vars
├── packages.yml                 dbt_utils, dbt_expectations
├── profiles.yml.example         Connection template (dbt Core)
├── .sqlfluff                    SQL style enforcement
├── .github/workflows/dbt_ci.yml Ephemeral-dataset CI: build + test + docs
├── macros/
│   ├── generate_schema_name.sql Clean schema names in prod, sandboxed in dev
│   ├── net_revenue.sql          Revenue rule reusable in ad-hoc analysis
│   └── cents_guard.sql          Consistent money rounding
├── models/
│   ├── staging/thelook/         7 staging models + source + model contracts
│   ├── intermediate/            3 ephemeral models holding the business logic
│   ├── marts/
│   │   ├── core/                fct_orders, fct_order_items, dim_customers, dim_products
│   │   ├── finance/             fct_daily_revenue, mart_product_performance
│   │   └── marketing/           mart_customer_cohorts, mart_acquisition_channels
│   └── semantic/                semantic_models.yml, metrics.yml, exposures.yml
├── tests/                       5 singular business-logic tests
└── analyses/                    Ad-hoc SQL compiled but never materialised
```

---

## Dashboards

All three read **marts and the metrics layer only** — never raw sources — and
are declared as dbt `exposures`, so they appear in the lineage graph and can be
selected in a build.

1. **Executive Revenue Overview** — net revenue, gross margin, AOV, order
   volume; 7-day trailing average and year-over-year comparison precomputed in
   `fct_daily_revenue`.
2. **Customer Cohort & Retention** — retention triangle, cumulative LTV curves,
   acquisition channel quality.
3. **Product & Category Performance** — revenue and margin by category, brand
   and price tier; return rates; in-category ranking.

---

## Performance notes

`fct_orders`, `fct_order_items` and `fct_daily_revenue` are **partitioned by
month** on their date column and **clustered** on their most common filter
columns. On BigQuery's on-demand pricing this is the difference between a
dashboard filter scanning one month and scanning the full table — it keeps the
whole project comfortably inside the 1 TB/month free tier.

Intermediate models are **ephemeral**: they are inlined as CTEs at compile
time, so they cost nothing to store and cannot be queried out of context by
someone who mistakes them for a mart.
