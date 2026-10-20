-- =============================================================================
-- 02 - Load the raw files into Bronze
-- =============================================================================
-- Prerequisite: the CSVs from data/raw/ are uploaded to the volume, e.g.
--
--   databricks fs cp -r data/raw/facebook_ads dbfs:/Volumes/bronze_production/cdc_staging/raw_files/facebook_ads
--   databricks fs cp -r data/raw/snapchat_ads dbfs:/Volumes/bronze_production/cdc_staging/raw_files/snapchat_ads
--
-- (or Catalog Explorer > bronze_production > cdc_staging > raw_files > Upload)
--
-- Bronze rules:
--   * every column is loaded as STRING (inferColumnTypes => false). Typing is
--     a transformation and belongs in dbt staging, where it is versioned and
--     tested. Type inference here would also silently turn the 18-digit
--     Facebook ids into DOUBLE and corrupt them.
--   * nothing is cleaned, renamed or filtered.
--   * two lineage columns are added: _loaded_at (drives dbt source freshness)
--     and _source_file.
--   * CREATE OR REPLACE makes the load idempotent for these static files. For
--     a recurring feed this would become COPY INTO / Auto Loader (append).
-- =============================================================================

USE CATALOG bronze_production;
USE SCHEMA cdc_staging;

-- ---------- Facebook Ads -----------------------------------------------------

CREATE OR REPLACE TABLE ads_stats
COMMENT 'Facebook Ads - daily stats per ad (raw).' AS
SELECT
    *,
    current_timestamp() AS _loaded_at,
    _metadata.file_path AS _source_file
FROM read_files(
    '/Volumes/bronze_production/cdc_staging/raw_files/facebook_ads/ads_stats.csv',
    format => 'csv', header => true, inferColumnTypes => false
);

CREATE OR REPLACE TABLE new_ads_de_randomized
COMMENT 'Facebook Ads - ads (raw).' AS
SELECT *, current_timestamp() AS _loaded_at, _metadata.file_path AS _source_file
FROM read_files(
    '/Volumes/bronze_production/cdc_staging/raw_files/facebook_ads/new_ads_de_randomized.csv',
    format => 'csv', header => true, inferColumnTypes => false
);

CREATE OR REPLACE TABLE new_adgroup_de_randomized
COMMENT 'Facebook Ads - ad sets (raw).' AS
SELECT *, current_timestamp() AS _loaded_at, _metadata.file_path AS _source_file
FROM read_files(
    '/Volumes/bronze_production/cdc_staging/raw_files/facebook_ads/new_adgroup_de_randomized.csv',
    format => 'csv', header => true, inferColumnTypes => false
);

CREATE OR REPLACE TABLE new_campaign_de_randomized
COMMENT 'Facebook Ads - campaigns (raw).' AS
SELECT *, current_timestamp() AS _loaded_at, _metadata.file_path AS _source_file
FROM read_files(
    '/Volumes/bronze_production/cdc_staging/raw_files/facebook_ads/new_campaign_de_randomized.csv',
    format => 'csv', header => true, inferColumnTypes => false
);

CREATE OR REPLACE TABLE new_acccount_de_randomized
COMMENT 'Facebook Ads - ad accounts (raw). Table name keeps the typo of the delivered file.' AS
SELECT *, current_timestamp() AS _loaded_at, _metadata.file_path AS _source_file
FROM read_files(
    '/Volumes/bronze_production/cdc_staging/raw_files/facebook_ads/new_acccount_de_randomized.csv',
    format => 'csv', header => true, inferColumnTypes => false
);

-- ---------- Snapchat Ads -----------------------------------------------------

CREATE OR REPLACE TABLE snapchat_ads_stats
COMMENT 'Snapchat Ads - daily stats per ad per country (raw).' AS
SELECT *, current_timestamp() AS _loaded_at, _metadata.file_path AS _source_file
FROM read_files(
    '/Volumes/bronze_production/cdc_staging/raw_files/snapchat_ads/snapchat_ads_stats.csv',
    format => 'csv', header => true, inferColumnTypes => false
);

CREATE OR REPLACE TABLE snapchat_ads_ad_history_new_ad_names
COMMENT 'Snapchat Ads - ads (raw).' AS
SELECT *, current_timestamp() AS _loaded_at, _metadata.file_path AS _source_file
FROM read_files(
    '/Volumes/bronze_production/cdc_staging/raw_files/snapchat_ads/snapchat_ads_ad_history_new_ad_names.csv',
    format => 'csv', header => true, inferColumnTypes => false
);

CREATE OR REPLACE TABLE snapchat_ads_adgroup_history_new_ad_group_names
COMMENT 'Snapchat Ads - ad group history, several versions per ad group (raw).' AS
SELECT *, current_timestamp() AS _loaded_at, _metadata.file_path AS _source_file
FROM read_files(
    '/Volumes/bronze_production/cdc_staging/raw_files/snapchat_ads/snapchat_ads_adgroup_history_new_ad_group_names.csv',
    format => 'csv', header => true, inferColumnTypes => false
);

CREATE OR REPLACE TABLE snapchat_ads_campaign_history_new_campaign_names
COMMENT 'Snapchat Ads - campaigns (raw).' AS
SELECT *, current_timestamp() AS _loaded_at, _metadata.file_path AS _source_file
FROM read_files(
    '/Volumes/bronze_production/cdc_staging/raw_files/snapchat_ads/snapchat_ads_campaign_history_new_campaign_names.csv',
    format => 'csv', header => true, inferColumnTypes => false
);

-- ---------- Check: row counts must match the files ---------------------------
--   ads_stats 92,300 | new_ads 98,926 | new_adgroup 13,433 | new_campaign 4,162
--   new_acccount 16 | snapchat_ads_stats 2,809 | snap ads 2,513
--   snap ad groups 267 | snap campaigns 109

SELECT 'ads_stats' AS table_name, count(*) AS row_count FROM ads_stats
UNION ALL SELECT 'new_ads_de_randomized', count(*) FROM new_ads_de_randomized
UNION ALL SELECT 'new_adgroup_de_randomized', count(*) FROM new_adgroup_de_randomized
UNION ALL SELECT 'new_campaign_de_randomized', count(*) FROM new_campaign_de_randomized
UNION ALL SELECT 'new_acccount_de_randomized', count(*) FROM new_acccount_de_randomized
UNION ALL SELECT 'snapchat_ads_stats', count(*) FROM snapchat_ads_stats
UNION ALL SELECT 'snapchat_ads_ad_history_new_ad_names', count(*) FROM snapchat_ads_ad_history_new_ad_names
UNION ALL SELECT 'snapchat_ads_adgroup_history_new_ad_group_names', count(*) FROM snapchat_ads_adgroup_history_new_ad_group_names
UNION ALL SELECT 'snapchat_ads_campaign_history_new_campaign_names', count(*) FROM snapchat_ads_campaign_history_new_campaign_names;
