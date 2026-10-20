-- =============================================================================
-- 03 - Unity Catalog permissions (run as a metastore / catalog admin)
-- =============================================================================
-- Replace before running:
--   6acc8d91-8fae-401a-a08a-58baae3c3291  Application ID of the production SP
--                                       (Settings > Identity and access >
--                                       Service principals > your SP)
--   bartvanuffelen10@gmail.com          your Databricks user (developer + CI)
--
-- Principle of least privilege:
--   * the Service Principal can READ bronze and WRITE silver/gold - nothing else
--   * developers/CI can READ bronze and WRITE only ci_development
--   * consumers (analysts, BI, AI agents) can only READ gold
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Production Service Principal
-- ---------------------------------------------------------------------------

-- Bronze: read the raw tables (sources)
GRANT USE CATALOG ON CATALOG bronze_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT USE SCHEMA ON CATALOG bronze_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT SELECT ON SCHEMA bronze_production.cdc_staging TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;

-- Silver: dbt creates the staging / intermediate / reference / elementary schemas
GRANT USE CATALOG ON CATALOG silver_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT USE SCHEMA ON CATALOG silver_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT CREATE SCHEMA ON CATALOG silver_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT CREATE TABLE ON CATALOG silver_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT SELECT ON CATALOG silver_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT MODIFY ON CATALOG silver_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;

-- Gold: dbt creates the marketing schema and its tables
GRANT USE CATALOG ON CATALOG gold_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT USE SCHEMA ON CATALOG gold_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT CREATE SCHEMA ON CATALOG gold_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT CREATE TABLE ON CATALOG gold_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT SELECT ON CATALOG gold_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;
GRANT MODIFY ON CATALOG gold_production TO `6acc8d91-8fae-401a-a08a-58baae3c3291`;

-- The SP also needs "Can use" on the SQL warehouse:
-- SQL Warehouses > <warehouse> > Permissions > add the SP with "Can use".


-- ---------------------------------------------------------------------------
-- Developer + CI (personal user; CI uses this user's token as a GitHub secret)
-- ---------------------------------------------------------------------------

-- Bronze: read sources
GRANT USE CATALOG ON CATALOG bronze_production TO `bartvanuffelen10@gmail.com`;
GRANT USE SCHEMA ON CATALOG bronze_production TO `bartvanuffelen10@gmail.com`;
GRANT SELECT ON SCHEMA bronze_production.cdc_staging TO `bartvanuffelen10@gmail.com`;

-- ci_development: full sandbox (create dbt_<you> and pr_<n> schemas)
GRANT USE CATALOG ON CATALOG ci_development TO `bartvanuffelen10@gmail.com`;
GRANT USE SCHEMA ON CATALOG ci_development TO `bartvanuffelen10@gmail.com`;
GRANT CREATE SCHEMA ON CATALOG ci_development TO `bartvanuffelen10@gmail.com`;
GRANT CREATE TABLE ON CATALOG ci_development TO `bartvanuffelen10@gmail.com`;
GRANT SELECT ON CATALOG ci_development TO `bartvanuffelen10@gmail.com`;
GRANT MODIFY ON CATALOG ci_development TO `bartvanuffelen10@gmail.com`;

-- Developers may read production gold to compare results, but never write it
GRANT USE CATALOG ON CATALOG gold_production TO `bartvanuffelen10@gmail.com`;
GRANT USE SCHEMA ON SCHEMA gold_production.marketing TO `bartvanuffelen10@gmail.com`;
GRANT SELECT ON SCHEMA gold_production.marketing TO `bartvanuffelen10@gmail.com`;


-- ---------------------------------------------------------------------------
-- Consumers: analysts, BI tools, AI agents  (run after the first production
-- deploy, when gold_production.marketing exists)
-- ---------------------------------------------------------------------------
-- Create a group "marketing_analysts" (Settings > Identity and access > Groups)
-- and add analysts / the BI or AI-agent service principal to it.

GRANT USE CATALOG ON CATALOG gold_production TO `marketing_analysts`;
GRANT USE SCHEMA ON SCHEMA gold_production.marketing TO `marketing_analysts`;
GRANT SELECT ON SCHEMA gold_production.marketing TO `marketing_analysts`;


-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
SHOW GRANTS `6acc8d91-8fae-401a-a08a-58baae3c3291` ON CATALOG silver_production;
SHOW GRANTS `6acc8d91-8fae-401a-a08a-58baae3c3291` ON CATALOG gold_production;
SHOW GRANTS `bartvanuffelen10@gmail.com` ON CATALOG ci_development;
