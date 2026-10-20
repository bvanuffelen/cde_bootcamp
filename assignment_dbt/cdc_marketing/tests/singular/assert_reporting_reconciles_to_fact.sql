-- The reporting table must show exactly the same totals as the fact it is
-- built from. Protects the consumer-facing table against join fan-out or
-- campaign rows lost in the aggregation.

with fact as (

    select
        sum(spend_eur) as spend_eur,
        sum(impressions) as impressions,
        sum(clicks) as clicks
    from {{ ref('fct_marketing_ad_performance_daily') }}

),

report as (

    select
        sum(spend_eur) as spend_eur,
        sum(impressions) as impressions,
        sum(clicks) as clicks
    from {{ ref('rpt_marketing_campaign_performance_daily') }}

)

select
    fact.spend_eur as fact_spend_eur,
    report.spend_eur as report_spend_eur,
    fact.impressions as fact_impressions,
    report.impressions as report_impressions,
    fact.clicks as fact_clicks,
    report.clicks as report_clicks
from fact
cross join report
where
    abs(fact.spend_eur - report.spend_eur) > 0.01
    or fact.impressions != report.impressions
    or fact.clicks != report.clicks
