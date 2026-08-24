# Setup — BigQuery + dbt

Do these in order. Budget ~45 minutes for a first run.

---

## 1. Google Cloud project (10 min)

1. Go to <https://console.cloud.google.com> and create a project, e.g.
   `thelook-analytics`. Note the **project ID** (not the display name).
2. Enable the **BigQuery API** (APIs & Services → Enable APIs → search BigQuery).
3. Billing: BigQuery's free tier gives **1 TB of query processing and 10 GB of
   storage per month**, and it does not expire. You do have to attach a billing
   account to create datasets, but this project will not approach the free tier
   ceiling — the partitioning and clustering in the mart configs is there
   precisely to keep scans small. Set a **budget alert at $1** anyway
   (Billing → Budgets & alerts) so there are no surprises.

**Verify the source data is reachable** — run this in the BigQuery console:

```sql
select count(*) as order_items
from `bigquery-public-data.thelook_ecommerce.order_items`;
```

You should get 181,758 rows. Public dataset queries are billed to
*your* project, so this counts against your free tier — it is a trivial amount.

---

## 2. Service account (5 min)

1. IAM & Admin → Service Accounts → **Create service account**, name it
   `dbt-runner`.
2. Grant it two roles: **BigQuery Data Editor** and **BigQuery Job User**.
   (Do *not* grant Owner — least privilege is worth a line in an interview.)
3. Keys → Add key → **Create new key → JSON**. Download it.
4. Put it somewhere outside the repo, e.g. `~/.gcp/dbt-runner.json`.
   The `.gitignore` here already blocks `*.json`, but never rely on that alone.

---

## 3. dbt (10 min)

### Option A — dbt Core (local, recommended for the portfolio)

```bash
python -m venv .venv && source .venv/bin/activate
pip install dbt-bigquery
cp profiles.yml.example ~/.dbt/profiles.yml
# edit ~/.dbt/profiles.yml: project id, dataset (dbt_harsh), keyfile path
dbt deps
dbt debug          # must print "All checks passed!"
```

### Option B — dbt Cloud (free Developer tier)

1. <https://cloud.getdbt.com> → new project → connection **BigQuery** → upload
   the service account JSON.
2. Development credentials → dataset `dbt_harsh`.
3. Point it at your GitHub repo, subdirectory blank (this repo is the root).

dbt Cloud is worth having *in addition* to Core: it hosts the docs site at a
shareable URL and it is the only way to query the semantic layer with
`dbt sl query`.

---

## 4. First build (5 min)

```bash
dbt build
```

`build` runs models and their tests in dependency order and stops a downstream
model from being built on data that just failed a test.

Expect on a first run:

- 7 staging views, 3 ephemeral (no objects created), 8 mart tables
- 128 tests
- ~76 seconds wall clock locally (8 threads); ~2m30s on a cold CI runner

If the `relationships` test on `stg_thelook__order_items.inventory_item_id`
warns, that is the source data, not your code — a small number of order items
reference inventory rows outside the window. Investigate the count before
deciding whether to change severity to `warn`; *that investigation is the
interesting part*, so write down what you find.

---

## 5. Docs (2 min)

```bash
dbt docs generate
dbt docs serve
```

Opens the lineage graph at localhost:8080. Screenshot the DAG — it is the
single most persuasive image for this project on a resume or portfolio site.

---

## 6. CI (10 min)

In your GitHub repo → Settings → Secrets and variables → Actions, add:

| Secret | Value |
|---|---|
| `BIGQUERY_PROJECT` | your GCP project id |
| `BIGQUERY_KEYFILE_JSON` | the full contents of the service account JSON |

Push to a branch and open a PR. `.github/workflows/dbt_ci.yml` builds every
model into a throwaway dataset named for the run id, runs every test, generates
docs, and drops the dataset afterwards.

Confirm it works by deliberately breaking something — change `net_revenue` in
`int_order_items_enriched.sql` to include cancelled items, push, and watch
`assert_cancelled_orders_have_zero_revenue` fail the build. **Screenshot the
red check.** That screenshot is the proof that the CI claim on your resume is
real, and it is exactly what an interviewer will ask about.

---

## 7. BI layer

Connect Power BI or Tableau to the **marts datasets only** (`*_core`,
`*_finance`, `*_marketing`). Do not let the BI tool see staging or the raw
public dataset — the point of the whole exercise is that the BI layer consumes
governed models.

Then fill in the real dashboard URLs in `models/semantic/exposures.yml`.

---

## Cost control

- **Measured cost of one full build:** 144 query jobs, **0.53 GiB processed** but
  **1.51 GiB billed** — roughly 0.15% of the 1 TB monthly free tier. You could run
  this pipeline ~660 times a month for free.
- **Why billed is 3x processed:** BigQuery bills a minimum of 10 MB per query. A
  build that is mostly 128 small test queries pays that floor over and over, so
  the bill is driven by job *count*, not data volume. This is the cost shape of a
  well-tested dbt project, and it is why `--select` matters more than table size
  when you are iterating.
- `dbt build --select staging` while iterating avoids rebuilding marts.
- BigQuery console shows estimated bytes scanned before you run a query — get
  in the habit of reading it.
- The CI workflow drops its dataset every run, so storage does not accumulate.
