-- Business questions from the case study, answered from the gold layer.
-- `dbt compile -s business_questions` renders the table names, then paste the
-- query you need into the Databricks SQL editor.
--
-- Two rules every query follows (and that an AI agent should follow too):
--   1. Sum spend_eur, never spend (accounts report in EUR and USD).
--   2. Recompute ratios from sums: sum(a) / nullif(sum(b), 0).
--      Never average the row-level ctr / cpc_eur / cpm_eur columns.


-- Q1-Q3  Total spend, and Facebook vs Snapchat
with by_platform as (
    select
        platform,
        sum(spend_eur) as spend_eur
    from {{ ref('rpt_marketing_campaign_performance_daily') }}
    group by platform
)

select
    platform,
    round(spend_eur, 2) as spend_eur,
    round(100 * spend_eur / sum(spend_eur) over (), 2) as pct_of_total
from by_platform
union all
select
    'TOTAL' as platform,
    round(sum(spend_eur), 2) as spend_eur,
    100 as pct_of_total
from by_platform
order by spend_eur;


-- Q4  Spend by campaign
select
    platform,
    campaign_name,
    round(sum(spend_eur), 2) as spend_eur
from {{ ref('rpt_marketing_campaign_performance_daily') }}
group by platform, campaign_name
order by spend_eur desc;


-- Q5 + Q8  Impressions and clicks per platform
select
    platform,
    sum(impressions) as impressions,
    sum(clicks) as clicks
from {{ ref('rpt_marketing_campaign_performance_daily') }}
group by platform
order by impressions desc;


-- Q6 + Q7  Campaigns with the most impressions and clicks
select
    platform,
    campaign_name,
    sum(impressions) as impressions,
    sum(clicks) as clicks,
    rank() over (order by sum(impressions) desc) as impressions_rank,
    rank() over (order by sum(clicks) desc) as clicks_rank
from {{ ref('rpt_marketing_campaign_performance_daily') }}
group by platform, campaign_name
order by impressions desc
limit 10;


-- Q9  CTR, CPC and CPM by platform
select
    platform,
    round(sum(spend_eur), 2) as spend_eur,
    sum(impressions) as impressions,
    sum(clicks) as clicks,
    round(100 * sum(clicks) / nullif(sum(impressions), 0), 3) as ctr_pct,
    round(sum(spend_eur) / nullif(sum(clicks), 0), 4) as cpc_eur,
    round(1000 * sum(spend_eur) / nullif(sum(impressions), 0), 4) as cpm_eur
from {{ ref('rpt_marketing_campaign_performance_daily') }}
group by platform;


-- Q10  Performance over time (month x platform)
select
    date_month,
    platform,
    round(sum(spend_eur), 2) as spend_eur,
    sum(impressions) as impressions,
    sum(clicks) as clicks,
    round(100 * sum(clicks) / nullif(sum(impressions), 0), 3) as ctr_pct,
    round(sum(spend_eur) / nullif(sum(clicks), 0), 4) as cpc_eur,
    round(1000 * sum(spend_eur) / nullif(sum(impressions), 0), 4) as cpm_eur
from {{ ref('rpt_marketing_campaign_performance_daily') }}
group by date_month, platform
order by date_month, platform;


-- Q11  Snapchat by country
select
    country_code,
    round(sum(spend), 2) as spend_eur,
    sum(impressions) as impressions,
    sum(clicks) as clicks
from {{ ref('fct_snapchat_ads_country_daily') }}
group by country_code
order by spend_eur desc;


-- Q12  "How much did we spend on Facebook last month?"
-- With live data use: date_month = date_trunc('month', add_months(current_date, -1))
-- The case-study files are static (Facebook ends 2025-12-31), so this
-- version takes the most recent month that has data.
select
    max(report.date_month) as month,
    round(sum(report.spend_eur), 2) as spend_eur
from {{ ref('rpt_marketing_campaign_performance_daily') }} as report
where
    report.platform = 'facebook'
    and report.date_month = (
        select max(latest.date_month)
        from {{ ref('rpt_marketing_campaign_performance_daily') }} as latest
        where latest.platform = 'facebook'
    );
