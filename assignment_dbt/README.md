# Marketing Data Platform: Facebook + Snapchat on Databricks with dbt

A small but production-minded data platform that loads raw Facebook Ads and Snapchat Ads
exports into Databricks, cleans and unifies them with dbt, and publishes one documented,
tested, governed marketing data product. Analysts, BI tools and AI agents can query it
without knowing how either platform structures its data.

```sql
-- "Compare Facebook and Snapchat spend" - one table, no platform knowledge needed
select platform, sum(spend_eur) as spend_eur
from gold_production.marketing.rpt_marketing_campaign_performance_daily
group by platform;
```

---

## Contents

1. [Architecture](#1-architecture)
2. [Repository structure](#2-repository-structure)
3. [The source data](#3-the-source-data)
4. [Data cleaning: what was found and what was done](#4-data-cleaning-what-was-found-and-what-was-done)
5. [Data model](#5-data-model)
6. [Materializations](#6-materializations)
7. [Data quality](#7-data-quality)
8. [Documentation, lineage and Elementary](#8-documentation-lineage-and-elementary)
9. [Environments](#9-environments)
10. [Production authentication and Unity Catalog permissions](#10-production-authentication-and-unity-catalog-permissions)
11. [CI/CD](#11-cicd)
12. [Step-by-step setup](#12-step-by-step-setup)
13. [Answering the business questions](#13-answering-the-business-questions)
14. [Consumption by BI and AI agents](#14-consumption-by-bi-and-ai-agents)
15. [Known limitations and next steps](#15-known-limitations-and-next-steps)

---

## 1. Architecture

```
 Facebook Ads exports (5 CSV)      Snapchat Ads exports (4 CSV)
              │                                │
              └──────────────┬─────────────────┘
                             ▼
              Unity Catalog volume  bronze_production.cdc_staging.raw_files
                             │  databricks/02_load_bronze.sql (read_files, all STRING)
                             ▼
 BRONZE   bronze_production.cdc_staging        9 raw tables, unchanged + _loaded_at
                             │
 ─────────────────────────── dbt ───────────────────────────────────────────────
                             ▼
 SILVER   silver_production.marketing_staging       stg_*  views: rename, type, standardise
          silver_production.marketing_intermediate  int_*  hierarchy flattening, union
          silver_production.marketing_reference     seed   FX rates
          silver_production.elementary              test history / observability
                             ▼
 GOLD     gold_production.marketing                 dim_* / fct_* / rpt_*
 ─────────────────────────────────────────────────────────────────────────────────
                             │
              ┌──────────────┼───────────────┐
              ▼              ▼               ▼
          Analysts       BI tools        AI agents
          (SQL)          (dashboards)    (natural language, reads UC comments)
```

Each layer has one job, and access is granted per layer:

| Layer | Contains | Who writes | Who reads |
|---|---|---|---|
| Bronze | raw files exactly as delivered | admin load script | dbt (dev, CI, prod) |
| Silver | cleaned, typed, conformed data | production Service Principal | data engineers |
| Gold | the marketing data product | production Service Principal | analysts, BI, AI agents |
| `ci_development` | developer and PR sandboxes | developers, CI | developers |

**dbt lineage**

```
source facebook_ads ─► stg_facebook_ads__* ─► int_facebook_ads__ads_enriched ─┐
                                                                              ├─► dim_marketing_ads ─────────┐
source snapchat_ads ─► stg_snapchat_ads__* ─► int_snapchat_ads__ads_enriched ─┘   dim_marketing_campaigns ─┐ │
                                                                                                           │ │
stg_*__ad_stats ─► int_marketing__ad_stats_unioned (ephemeral) ─► fct_marketing_ad_performance_daily ◄────┼─┘
seed fx_rates_annual ─────────────────────────────────────────────────┘          │                        │
                                                                                  ▼                        │
                                                    rpt_marketing_campaign_performance_daily ◄─────────────┘
stg_snapchat_ads__ad_stats ─► fct_snapchat_ads_country_daily
```

`dbt docs generate` renders this graph interactively (see [section 8](#8-documentation-lineage-and-elementary)).

---

## 2. Repository structure

```
<your repo>/
├── .github/                           ← must live at the repo ROOT (GitHub only runs workflows from there)
│   ├── actions/setup-dbt-assignment/  ← shared step: uv sync + dbt deps
│   └── workflows/
│       ├── dbt_ci.yml                   PR → lint + build/test in ci_development.pr_<n>
│       ├── dbt_pr_cleanup.yml           PR closed → drop pr_<n>
│       └── dbt_deploy_production.yml    merge to main → build as Service Principal + reports
└── assignment_dbt/                    ← this project
    ├── README.md                      ← you are here
    ├── pyproject.toml / uv.lock       ← pinned Python toolchain (dbt, dbt-databricks, elementary, sqlfluff)
    ├── data/raw/                      ← the provided source files, unchanged
    │   ├── facebook_ads/   (5 CSV)
    │   └── snapchat_ads/   (4 CSV)
    ├── databricks/                    ← one-off platform setup, run in a Databricks SQL editor
    │   ├── 01_create_catalogs.sql       catalogs, schema, volume
    │   ├── 02_load_bronze.sql           CSV → Bronze tables
    │   └── 03_grants.sql                Unity Catalog permissions
    └── cdc_marketing/                 ← the dbt project
        ├── dbt_project.yml / profiles.yml / packages.yml / .env.template
        ├── .sqlfluff                    SQL style rules (enforced in CI)
        ├── macros/                      generate_schema_name, generate_database_name, drop_ci_schema
        ├── models/
        │   ├── staging/facebook_ads/    5 models + sources + tests
        │   ├── staging/snapchat_ads/    4 models + sources + tests
        │   ├── intermediate/            per-platform enrichment + the cross-platform union
        │   └── mart/
        │       ├── dim/                 dim_marketing_ads, dim_marketing_campaigns
        │       ├── fact/                fct_marketing_ad_performance_daily, fct_snapchat_ads_country_daily
        │       └── reporting/           rpt_marketing_campaign_performance_daily
        ├── seeds/fx_rates_annual.csv
        ├── tests/singular/              reconciliation tests
        └── analyses/business_questions.sql
```

The workflows only trigger when something under `assignment_dbt/` (or the workflows
themselves) changes, so the rest of the repository is unaffected.

Naming conventions: `stg_<source>__<entity>`, `int_<scope>__<description>`, `dim_` / `fct_`
for the star schema, `rpt_` for consumer-ready wide tables. All SQL is lowercase and
linted by SQLFluff.

---

## 3. The source data

| Platform | File | Rows | Grain | Role |
|---|---|---:|---|---|
| Facebook | `ads_stats.csv` | 92,300 | ad × day | **performance** |
| Facebook | `new_ads_de_randomized.csv` | 98,926 | ad | ad → ad set, campaign, account |
| Facebook | `new_adgroup_de_randomized.csv` | 13,433 | ad set | ad set names |
| Facebook | `new_campaign_de_randomized.csv` | 4,162 | campaign | campaign names |
| Facebook | `new_acccount_de_randomized.csv` | 16 | account | account names, **currency** |
| Snapchat | `snapchat_ads_stats.csv` | 2,809 | ad × day × **country** | **performance** |
| Snapchat | `snapchat_ads_ad_history_new_ad_names.csv` | 2,513 | ad | ad → ad group |
| Snapchat | `snapchat_ads_adgroup_history_new_ad_group_names.csv` | 267 | ad group **version** | ad group → campaign |
| Snapchat | `snapchat_ads_campaign_history_new_campaign_names.csv` | 109 | campaign | campaign → account |

Both platforms share the hierarchy **account → campaign → ad group → ad** and report
performance at the **ad** level. They model it differently, though:

| Concept | Facebook | Snapchat | Unified name |
|---|---|---|---|
| ad id | `ad_id` (18-digit number) | `ad_detail_id` in stats, `ad_id` elsewhere (UUID) | `ad_id` (STRING) |
| ad group | "ad set" (`new_adgroup`) | ad group (history table) | `ad_group_id`, `ad_group_name` |
| path ad → campaign | direct (`campaign_id` on the ad) | via the ad group | `campaign_id` |
| path campaign → account | via the ads (campaign has no account) | direct | `account_id` |
| currency | on the **account** (EUR or USD) | on every **stats row** (EUR) | `currency_code` |
| country | not reported | `ad_country` on stats | `country_code` (Snapchat model only) |
| date | `ad_date` | `ad_date` | `date_day` |
| metrics | `ad_spend`, `ad_impressions`, `ad_clicks` | same names | `spend`, `impressions`, `clicks` |

**Coverage:** Facebook covers 2025-01-01 to 2025-12-31 (all 365 days). Snapchat covers
2024-01-01 to 2024-12-02, on 133 days only.

---

## 4. Data cleaning: what was found and what was done

Every file was profiled before modelling. Each finding below became an explicit rule, it
is implemented in exactly one place, and where possible a test protects it.

| # | Finding (measured on the provided files) | Decision | Where | Protected by |
|---|---|---|---|---|
| 1 | Missing values are the **text** `'null'`, not empty: 24,337 Facebook click values, 1,474 Facebook impression values, 111 Snapchat click values | Load everything as STRING in Bronze; `try_cast` in staging turns `'null'` into a real NULL | `02_load_bronze.sql`, `stg_*__ad_stats` | `accepted_range` tests on metrics |
| 2 | Facebook ids have up to 18 digits; **46 % of ad ids exceed 2^53**, so as DOUBLE they would be silently rounded and joins would break | All ids are STRING, everywhere | all staging models | `relationships` tests (a corrupted id would fail them) |
| 3 | A NULL metric means "the platform reported nothing", not "unknown" | `coalesce(…, 0)` for impressions and clicks in the union. Staging keeps the NULLs, so it still mirrors the source. | `int_marketing__ad_stats_unioned` | `not_null` on fact metrics |
| 4 | **6,458** Facebook rows have 0 spend, 0/NULL impressions and 0/NULL clicks: no information | Dropped from the fact | `int_marketing__ad_stats_unioned` | `assert_spend_reconciles_source_to_fact` proves no spend was dropped |
| 5 | **Snapchat stats are per ad per day per country** (de, ch, at and a single `us` row). They are not unique on ad + day: 2,809 rows → 1,052 ad-days. | Summed to ad × day for the unified fact. The country detail is kept in `fct_snapchat_ads_country_daily`. | union model; country fact | `unique_combination_of_columns` on both grains |
| 6 | **Mixed currencies:** 1 Facebook account reports in EUR (€2.56 M), 2 report in **USD** ($6.87 M). Snapchat is EUR. A naive `sum(spend)` gives 9.46 M "money", overstating EUR spend by about €0.79 M (9 %). | Keep `spend` + `currency_code`, and add `spend_eur` using ECB annual average rates (seed). `spend_eur` is *the* business definition of spend. | fact model, `seeds/fx_rates_annual.csv` | `fct_marketing_fx_rate_available` fails the build if a rate is missing |
| 7 | The Snapchat ad-group file is a **history** table: 3 ad groups have 2 versions | Keep only the latest version (`qualify row_number() … = 1`) before joining. Without this, those ads' spend would be doubled. | `int_snapchat_ads__ads_enriched` | `unique` on `ad_id`, spend reconciliation |
| 8 | **304 Snapchat ads** (85 ad groups) reference ad groups missing from the export | Kept, with NULL campaign. None of them have stats, so no spend is affected. Flagged as a **warning** for the source owner. | enriched model, `dim_marketing_ads` | `relationships` / `not_null` with `severity: warn` |
| 9 | Facebook campaigns have **no `account_id`** | Derived from their ads (verified: every campaign maps to exactly one account) | `dim_marketing_campaigns` | `unique` on `campaign_key` |
| 10 | Ad and campaign ids are only unique **within** a platform | Surrogate keys hash the platform with the id | all marts | `unique` on every surrogate key |
| 11 | 687 Facebook rows have impressions but 0 spend (bonus or free delivery) | Kept as valid. Not an error. | n/a | none |
| 12 | Clicks never exceed impressions, there are no negative values and no future dates | Codified so it stays that way | n/a | `clicks <= impressions`, `accepted_range ≥ 0`, `date_day <= current_date` |
| 13 | Platforms don't overlap in time. Snapchat has **no data for April, May and October 2024**. | Documented in the model descriptions, since it is not fixable in the data | model docs | Elementary volume anomalies on new loads |
| 14 | History-style tables (Facebook ads, ad sets, campaigns, accounts) carry `updated_at` | Deduplicated to the latest version as well, even though today they are unique. A second version tomorrow cannot fan out a join. | `int_facebook_ads__ads_enriched` | `unique` on `ad_id` |

Result: **92,300 + 2,809 raw stats rows → 86,894 fact rows** (85,842 Facebook ad-days and
1,052 Snapchat ad-days). Total spend reconciles to the cent between staging and the fact.

---

## 5. Data model

A small star schema, plus one wide reporting table for consumers:

| Model | Grain (one row = …) | Key | Purpose |
|---|---|---|---|
| `fct_marketing_ad_performance_daily` | one **ad** on one **platform** on one **day** | `ad_performance_id` = hash(platform, ad_id, date_day) | the unified fact: additive metrics only |
| `dim_marketing_ads` | one ad on one platform | `ad_key` = hash(platform, ad_id) | ad → ad group → campaign → account |
| `dim_marketing_campaigns` | one campaign on one platform (incl. never-spent) | `campaign_key` = hash(platform, campaign_id) | campaign attributes |
| `rpt_marketing_campaign_performance_daily` | one **campaign** on one platform on one day | `campaign_performance_id` | **start here**: names + KPIs, built for BI/AI |
| `fct_snapchat_ads_country_daily` | one Snapchat ad on one day in one country | `snapchat_country_performance_id` | country detail only Snapchat has |

**Why this design**

- **The fact is at ad level, not campaign level.** It is the lowest grain both platforms
  share, so every rollup (ad group, campaign, account, platform) is possible from one model.
- **The fact is narrow.** It holds keys and additive metrics only. Names live in the
  dimensions. If a campaign is renamed, the incremental fact never holds stale names
  (old rows outside the lookback window are not rewritten).
- **Ratios are not stored in the fact.** CTR, CPC and CPM cannot be summed or averaged
  across rows. They appear in the reporting table *per row*, and the documentation tells
  consumers to recompute them from sums.
- **A wide reporting table for consumers.** Most questions are at campaign × day. One
  denormalised, fully documented table with readable names is the easiest thing for an
  analyst, a dashboard or an LLM to query correctly. It is rebuilt in full every run,
  so names are always current.

**Business definitions**

| Metric | Definition | Zero handling |
|---|---|---|
| Spend | `spend_eur`: spend converted to EUR at the ECB annual average rate | n/a |
| Impressions | times an ad was shown | NULL in source → 0 |
| Clicks | clicks on an ad | NULL in source → 0 |
| CTR | clicks / impressions | NULL when impressions = 0 |
| CPC | spend_eur / clicks | NULL when clicks = 0 (a CPC of 0 would claim clicks were free) |
| CPM | spend_eur / impressions × 1,000 | NULL when impressions = 0 |

The fact table's **contract is enforced**: column names and data types are fixed, and a
change that would break consumers fails the build instead of reaching them.

---

## 6. Materializations

| Model(s) | Materialization | Why |
|---|---|---|
| `stg_*` | **view** | Thin rename/cast layer over small tables. No storage, always current, and the cost is paid only when read. |
| `int_*__ads_enriched` | **table** | Window-function dedup plus 3–4 joins over ~100k ads, read by several marts. Computing it once is cheaper than recomputing it per consumer. |
| `int_marketing__ad_stats_unioned` | **ephemeral** | One consumer (the fact). Inlined as a CTE, so the fact's incremental filter is pushed down into it and nothing is stored twice. |
| `fct_marketing_ad_performance_daily` | **incremental**, `merge` on `ad_performance_id` | The table that grows daily. Each run only reprocesses recent days. See below. |
| `dim_*`, `rpt_*`, country fact | **table** | 3k–100k rows that rebuild in seconds. A full rebuild keeps them always consistent (renames, deletes) without incremental bookkeeping. |
| `fx_rates_annual` | **seed** | Small, slowly changing reference data that belongs in version control. |

**How the incremental fact works**

```sql
-- per platform: reprocess from (latest loaded day - 3 days)
watermarks as (
    select platform, dateadd(day, -3, max(date_day)) as reprocess_from
    from {{ this }} group by platform
)
```

- **Lookback (3 days, `var: marketing_lookback_days`).** Ad platforms restate spend and
  clicks for several days after delivery. Reprocessing the last days picks up those
  corrections, and `merge` on the unique key makes reprocessing idempotent (no duplicates).
- **Watermark per platform, not global.** Platforms deliver on their own schedules. In this
  data Snapchat ends a full year before Facebook, so a single `max(date_day)` would put
  Snapchat permanently "behind the watermark" and silently skip any new Snapchat data.
  A platform that has never been loaded gets a full load.
- **Liquid clustering** on `(platform, date_day)` matches the usual filters.
- **Verified:** on a second run only Facebook 2025-12-28..31 and Snapchat 2024-11-29..12-02
  were rewritten, and row counts were unchanged.
- `dbt build --full-refresh` rebuilds it from scratch (CI always does this).

---

## 7. Data quality

**123 data tests** run on every `dbt build`. They are chosen to protect the analytical
model, not to tick a box:

| Category | Examples | What it protects against |
|---|---|---|
| Primary keys | `unique` + `not_null` on every surrogate key; `unique_combination_of_columns` on every declared grain | duplicated rows inflating totals; the grain silently changing |
| Referential integrity | `relationships`: stats → ads → ad groups → campaigns; fact → `dim_marketing_ads` and `dim_marketing_campaigns` | rows that vanish from campaign reports because their key doesn't join |
| Accepted values | `platform in (facebook, snapchat)`, `currency_code in (EUR, USD)`, Facebook `ad_status`, Snapchat `country_code` | an unmapped new platform/currency/country (warn for countries, error for currency) |
| Reasonable values | `spend, impressions, clicks >= 0`, `clicks <= impressions`, `0 <= ctr <= 1`, no future dates | broken exports and unit mistakes |
| Business rules | `fct_marketing_fx_rate_available`: every row must have `spend_eur` | a new year/currency without an FX rate silently understating spend |
| Reconciliation (singular) | `assert_spend_reconciles_source_to_fact`, `assert_reporting_reconciles_to_fact` | fan-out joins and dropped rows, which column-level tests cannot see |
| Observability (Elementary) | `volume_anomalies`, `schema_changes` on the fact | a load that is suddenly much smaller or larger, or upstream schema drift |
| Source freshness | `_loaded_at` warn after 2 days | a feed that stopped arriving |

**Severity is deliberate.** Errors block deploys. Warnings (orphan Snapchat ad groups,
unexpected countries, Elementary anomalies) are known data issues or signals that need a
human, and blocking production on them would only hide the dashboard. Current result:
**120 pass, 3 warn, 0 fail**. All 3 warnings are the 304 orphan Snapchat ads (finding #8), seen at
three layers.

---

## 8. Documentation, lineage and Elementary

**dbt docs.** Every source, model, key column and metric has a description. Every model
description states its grain.

```bash
cd cdc_marketing
dbt docs generate --static        # → target/static_index.html (single self-contained file)
dbt docs serve                    # or browse it locally with the interactive lineage graph
```

CI attaches `static_index.html` to every PR run, and the production deploy attaches it to
every deploy (*Actions → run → Artifacts*).

`persist_docs` is enabled for the marts, so the same descriptions are written to
**Unity Catalog table and column comments**. Catalog Explorer, BI tools and AI agents see
the documentation next to the data.

**Elementary.** The Elementary dbt package runs with every `dbt build` and stores
each run's test and model results in `silver_production.elementary`. That gives a history
of failures, durations and row counts. The production workflow then renders the report:

```bash
edr report --profiles-dir . --profile-target production --file-path edr_target/elementary_report.html
```

The report shows test results over time, failed tests with sample rows, model health and
run durations, volume anomalies and schema changes. It is uploaded as an artifact of
every production run. `edr send-report` can publish it to S3/GCS or Slack as a next step.

---

## 9. Environments

| | **dev** (development) | **ci** | **production** |
|---|---|---|---|
| Purpose | build and try models while developing | validate a pull request before merge | serve consumers |
| Trigger | developer runs dbt locally | every push to a PR into `main` | merge to `main`, daily 05:00 UTC, manual |
| Catalog | `ci_development` | `ci_development` | `silver_production` + `gold_production` |
| Schema | `dbt_<developer>` (one per person) | `pr_<PR number>` (one per PR, dropped on close) | `marketing_staging`, `marketing_intermediate`, `marketing_reference`, `elementary`, `marketing` |
| Credentials | developer's personal access token | developer token stored as a GitHub secret | **Service Principal, OAuth M2M** |
| Sources read | `bronze_production` (read-only) | `bronze_production` (read-only) | `bronze_production` (read-only) |

How it's implemented:

- **One dbt profile, three targets** (`profiles.yml`), selected with `DBT_TARGET`. The file
  contains no secrets, only `env_var()` lookups.
- `macros/generate_database_name.sql` and `generate_schema_name.sql` route models to the
  silver/gold catalogs and per-layer schemas **only in production**. In dev and CI every
  model lands in the single target schema inside `ci_development`. A non-production run
  can't write to a production catalog, and a developer's or PR's tables are isolated and
  easy to drop.
- All environments read the same Bronze sources, so CI tests run on real data. The data
  is small enough (95k rows) that CI builds everything instead of a sample, so tests see
  exactly what production will see.

---

## 10. Production authentication and Unity Catalog permissions

**Service Principal.** Production never uses a personal access token. The production
workflow authenticates as a Databricks **Service Principal** through **OAuth
machine-to-machine** (`auth_type: oauth` with `client_id` / `client_secret` in the
`production` target). The credentials exist only as secrets of the GitHub environment
`production`. Production therefore keeps working when a developer leaves or their token
expires, every change to production data is attributable to the SP, and the SP's rights
are exactly what production needs.

**Unity Catalog permissions** (`databricks/03_grants.sql`) follow least privilege:

| Principal | bronze_production | silver_production | gold_production | ci_development |
|---|---|---|---|---|
| Production Service Principal | USE + SELECT on `cdc_staging` | USE, CREATE SCHEMA/TABLE, SELECT, MODIFY | USE, CREATE SCHEMA/TABLE, SELECT, MODIFY | none |
| Developer / CI (your user) | USE + SELECT on `cdc_staging` | none | SELECT on `marketing` (to compare) | USE, CREATE SCHEMA/TABLE, SELECT, MODIFY |
| `marketing_analysts` group (people, BI, AI agent) | none | none | USE + SELECT on `marketing` | none |

The SP also needs **Can use** on the SQL warehouse.

---

## 11. CI/CD

```
feature branch ──► pull request ──► CI ─────────────────────────────┐
                                    1. sqlfluff lint                 │ required check
                                    2. dbt debug                     │ (branch protection
                                    3. dbt build --full-refresh      │  on main)
                                       → ci_development.pr_<n>       │
                                    4. source freshness (info)       │
                                    5. docs → artifact               │
                                                                     ▼
                                   review + merge ──► Deploy production (Service Principal)
                                                      1. dbt debug
                                                      2. dbt source freshness
                                                      3. dbt build
                                                      4. docs + Elementary report → artifacts
                     PR closed ──► PR cleanup: drop ci_development.pr_<n>
```

| Workflow | File | Credentials |
|---|---|---|
| CI | `.github/workflows/dbt_ci.yml` | `DATABRICKS_CI_TOKEN` (repository secret) |
| PR cleanup | `.github/workflows/dbt_pr_cleanup.yml` | `DATABRICKS_CI_TOKEN` |
| Deploy production | `.github/workflows/dbt_deploy_production.yml` | `DATABRICKS_SP_CLIENT_ID` / `_SECRET` (environment `production`) |

Design choices:

- **Full build in CI, not "slim CI".** With 95k rows, a full build takes a couple of
  minutes and tests every model on real data. Slim CI (`state:modified+` against the
  production manifest) is the upgrade path once the project grows.
- **`--full-refresh` in CI.** A PR is validated the way production builds it from scratch,
  so earlier pushes to the same PR leave no state behind.
- **Lint before build.** Style problems fail in seconds, before warehouse time is spent.
- **Reproducible toolchain.** `uv.lock` pins every Python package, so CI, production and
  laptops run identical versions of dbt, the adapter and Elementary.
- **`concurrency`** cancels outdated CI runs of a PR, and never runs two production
  deploys at once.
- **The GitHub environment `production`** scopes the SP secrets to the deploy job, and can
  require a reviewer's approval before production runs.

---

## 12. Step-by-step setup

### Prerequisites
- A Databricks workspace with Unity Catalog and a SQL warehouse
- Admin rights to create catalogs, a Service Principal and grants
- Python 3.11+ and [uv](https://docs.astral.sh/uv/), the Databricks CLI (optional, for uploads)
- A GitHub repository

### Step 1: Create the Service Principal
1. *Settings → Identity and access → Service principals → Add service principal*, name it
   for example `sp-marketing-dbt-prod`.
2. Open it → *Secrets* → **Generate secret**. Copy the **Client ID** (= Application ID) and
   the **secret** (shown once).
3. *SQL Warehouses → your warehouse → Permissions* → give the SP **Can use**.

### Step 2: Create catalogs and the landing volume
Run `databricks/01_create_catalogs.sql` in the SQL editor.

### Step 3: Upload the raw files and load Bronze
```bash
cd <repo>/assignment_dbt
databricks fs cp -r data/raw/facebook_ads dbfs:/Volumes/bronze_production/cdc_staging/raw_files/facebook_ads
databricks fs cp -r data/raw/snapchat_ads dbfs:/Volumes/bronze_production/cdc_staging/raw_files/snapchat_ads
```
(or upload the two folders through Catalog Explorer), then run
`databricks/02_load_bronze.sql`. The final query must show the row counts listed in the
script (92,300 … 109). Databricks may add a `_rescued_data` column, which is harmless and
ignored by staging.

### Step 4: Apply the permissions
In `databricks/03_grants.sql`, replace `<SERVICE_PRINCIPAL_APPLICATION_ID>` (and the email,
if needed) and run it. The `marketing_analysts` block runs after the first production
deploy (step 9).

### Step 5: Set up your machine
```bash
git clone <repo> && cd <repo>/assignment_dbt
uv sync                                   # installs the locked toolchain into .venv
cd cdc_marketing
cp .env.template .env                     # fill in host, http path, your token, DBT_DEV_SCHEMA
set -a && source .env && set +a
uv run dbt deps
uv run dbt debug                          # "All checks passed!"
```

### Step 6: Build in your dev schema
```bash
uv run dbt build                          # seeds, models and tests → ci_development.dbt_<you>
uv run dbt source freshness
uv run sqlfluff lint models tests analyses
```
Expected: `PASS=169 WARN=3 ERROR=0` (49 models incl. Elementary's, 1 seed, 123 tests).

### Step 7: Look at the docs
```bash
uv run dbt docs generate && uv run dbt docs serve     # lineage graph at localhost:8080
```

### Step 8: Configure GitHub
*Settings → Secrets and variables → Actions*:

| Secret | Scope | Value |
|---|---|---|
| `DATABRICKS_HOST` | repository | `dbc-xxxx.cloud.databricks.com` |
| `DATABRICKS_HTTP_PATH` | repository | `/sql/1.0/warehouses/…` |
| `DATABRICKS_CI_TOKEN` | repository | personal access token for CI |
| `DATABRICKS_SP_CLIENT_ID` | environment `production` | SP Client ID (step 1) |
| `DATABRICKS_SP_CLIENT_SECRET` | environment `production` | SP secret (step 1) |

Create the environment under *Settings → Environments → New environment → `production`*.
Then add a branch protection rule on `main` requiring the **dbt CI / dbt build (ci)** and
**dbt CI / Lint SQL** checks. Because the workflows only run for changes under
`assignment_dbt/`, a *required* check would block PRs that touch other folders. If the
repo holds other work, leave the checks optional or use a ruleset scoped to these paths.

### Step 9: First change, end to end
```bash
git checkout -b feature/my-change
# … edit a model …
git commit -am "Describe the change" && git push -u origin feature/my-change
```
Open a PR. CI builds `ci_development.pr_<n>` and attaches the docs. After merge,
*Deploy production* builds `gold_production.marketing` as the Service Principal and
attaches the docs and the Elementary report. The PR schema is dropped. Now run the
`marketing_analysts` grants from step 4.

### Step 10: Verify production
```sql
select platform, count(*), sum(spend_eur)
from gold_production.marketing.fct_marketing_ad_performance_daily
group by platform;
-- facebook  85,842 rows  8,641,797.40
-- snapchat   1,052 rows     30,529.55
```

---

## 13. Answering the business questions

All queries are in `cdc_marketing/analyses/business_questions.sql`. Results on the
provided data:

**Spend, impressions, clicks: Facebook vs Snapchat**

| Platform | Spend (EUR) | Share | Impressions | Clicks | CTR | CPC | CPM |
|---|---:|---:|---:|---:|---:|---:|---:|
| Facebook | 8,641,797.40 | 99.65 % | 905,449,421 | 5,737,710 | 0.634 % | €1.51 | €9.54 |
| Snapchat | 30,529.55 | 0.35 % | 33,395,784 | 19,012 | 0.057 % | €1.61 | €0.91 |
| **Total** | **8,672,326.95** | 100 % | 938,845,205 | 5,756,722 | | | |

On Snapchat, impressions cost about a tenth of Facebook's (CPM €0.91 vs €9.54), but users
click about 11× less, so a click costs roughly the same on both platforms (≈ €1.5–1.6).

```sql
-- What is the cost per click / per 1,000 impressions per platform?
select
    platform,
    sum(spend_eur) / nullif(sum(clicks), 0)              as cpc_eur,
    1000 * sum(spend_eur) / nullif(sum(impressions), 0)  as cpm_eur
from gold_production.marketing.rpt_marketing_campaign_performance_daily
group by platform;
```

**Top campaigns**

| | Campaign | Value |
|---|---|---:|
| Most impressions **and** clicks | `usa_ios_display_ggl_awareness_20230916_interest-stack-v3_video-views` | 84.0 M impressions, 1.39 M clicks |
| Most spend | `gbr_app_influencer_met_retargeting_20230728_lifetime-offer-v2_website-visits` | €1,122,799 |

```sql
-- Which campaigns generate the most impressions and clicks?
select platform, campaign_name, sum(impressions) as impressions, sum(clicks) as clicks
from gold_production.marketing.rpt_marketing_campaign_performance_daily
group by platform, campaign_name
order by impressions desc
limit 10;
```

**Performance over time** (monthly, Facebook 2025)

| Month | Spend (EUR) | CTR | CPC |
|---|---:|---:|---:|
| 2025-01 | 1,152,925 | 0.49 % | €1.69 |
| 2025-02 | 677,632 | 0.41 % | €2.59 |
| 2025-06 | 716,944 | 0.89 % | €1.25 |
| 2025-10 | 575,720 | 0.78 % | €0.95 |
| 2025-12 | 679,881 | 0.74 % | €1.34 |

CTR rose from about 0.4–0.5 % in Q1 to 0.65–0.9 % from Q2 onwards. The cost per click
fell with it, from €2.59 in February to €0.95 in October.

**Snapchat by country:** Germany €18,559, Switzerland €7,608, Austria €4,363 (and one
3-cent row in the US).

**"How much did we spend on Facebook last month?"** The latest month with data is
December 2025: **€679,880.60**.

---

## 14. Consumption by BI and AI agents

The gold layer is designed to be queried correctly by someone, or something, that has
never seen Facebook or Snapchat data:

- **One obvious entry point.** `rpt_marketing_campaign_performance_daily` is described as
  "Start here", with readable names and the KPIs pre-computed.
- **Self-describing tables.** Model and column descriptions, including the grain, units,
  zero handling and the "sum `spend_eur`, recompute ratios" rule, are pushed into Unity
  Catalog comments (`persist_docs`). An AI agent reading the catalog sees them.
- **Unambiguous columns.** `spend_eur` (not `spend`), lowercase platform values, an
  explicit `date_month`, and NULL instead of misleading zeros.
- **Stable interface.** The enforced contract on the fact means column names and types
  don't change under consumers.
- **Trust.** Every number has passed 123 tests, and reconciliation proves totals match
  the source.
- **Governed access.** Consumers (including an AI agent's service principal) are added to
  `marketing_analysts` and can read only gold.

Example natural-language questions and the table that answers them:

| Question | Answer from |
|---|---|
| "How much did we spend on Facebook last month?" | `rpt_…` filtered on `platform` and `date_month` |
| "Which campaign had the highest number of clicks?" | `rpt_…` grouped by `campaign_name` |
| "Compare Facebook and Snapchat spend." | `rpt_…` grouped by `platform` |
| "Which country is cheapest on Snapchat?" | `fct_snapchat_ads_country_daily` |

---

## 15. Known limitations and next steps

| Limitation | Next step |
|---|---|
| FX uses **annual average** rates | Daily ECB rates as a source table, joined on `date_day` |
| The platforms have **no overlapping period** in the provided files | Nothing to fix in the data. Comparisons over time need overlapping exports. |
| Bronze load is a one-off `CREATE OR REPLACE` of static files | Auto Loader / `COPY INTO` from a landing volume for daily incremental files |
| Only the latest version of Snapchat ad groups is used | A dbt **snapshot** (SCD2) if historical names are needed |
| 304 Snapchat ads without an ad group | Raise with the source owner, since the warning stays visible in Elementary |
| CI uses a developer token | A dedicated CI Service Principal, scoped to `ci_development` |
| Full CI build | Slim CI (`--select state:modified+ --defer`) once build time matters |
| Reports are workflow artifacts | Host docs on GitHub Pages, and send the Elementary report to Slack or a bucket |
| Campaign names encode market, OS, objective and more | Parse them into dimension attributes (`market`, `objective`, …) for richer slicing |
