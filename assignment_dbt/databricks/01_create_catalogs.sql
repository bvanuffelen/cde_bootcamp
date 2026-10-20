-- =============================================================================
-- 01 - Unity Catalog structure (run once, as a workspace / metastore admin)
-- =============================================================================
--
--   bronze_production   raw files exactly as delivered       (written by: admin load)
--     └─ cdc_staging      9 raw tables + raw_files volume
--   silver_production   cleaned & conformed data              (written by: Service Principal)
--     ├─ marketing_staging        stg_* views
--     ├─ marketing_intermediate   int_* tables
--     ├─ marketing_reference      seeds (FX rates)
--     └─ elementary               test history / observability
--   gold_production     consumption layer                     (written by: Service Principal)
--     └─ marketing                dim_*, fct_*, rpt_* - what analysts, BI and AI read
--   ci_development      dev + CI sandboxes                    (written by: developers)
--     ├─ dbt_<developer>          one schema per developer
--     └─ pr_<number>              one schema per pull request, dropped on close
--
-- Medallion catalogs separate *what the data is* (raw / clean / consumable),
-- so access can be granted per layer: analysts only ever get gold.
-- =============================================================================

CREATE CATALOG IF NOT EXISTS bronze_production
COMMENT 'Raw advertising exports, loaded unchanged (Bronze).';

CREATE SCHEMA IF NOT EXISTS bronze_production.cdc_staging
COMMENT 'Raw Facebook Ads and Snapchat Ads files.';

CREATE VOLUME IF NOT EXISTS bronze_production.cdc_staging.raw_files
COMMENT 'Landing zone for the provided CSV files.';

CREATE CATALOG IF NOT EXISTS silver_production
COMMENT 'Cleaned, typed and conformed marketing data (Silver). Built by dbt.';

CREATE CATALOG IF NOT EXISTS gold_production
COMMENT 'Unified marketing data product for analysts, BI and AI agents (Gold). Built by dbt.';

CREATE CATALOG IF NOT EXISTS ci_development
COMMENT 'Developer and CI sandboxes. Never read by consumers.';
