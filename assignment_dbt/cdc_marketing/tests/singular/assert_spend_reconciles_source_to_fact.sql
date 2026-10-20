-- No spend may be lost or duplicated between staging and the unified fact.
-- Column tests cannot catch a fan-out join (e.g. an un-deduplicated ad group
-- version) or rows dropped by a filter - a reconciliation of totals can.
-- Returns one row per platform whose totals differ by more than 1 cent.

with staging_totals as (

    select
        'facebook' as platform,
        sum(coalesce(spend, 0)) as spend
    from {{ ref('stg_facebook_ads__ad_stats') }}

    union all

    select
        'snapchat' as platform,
        sum(coalesce(spend, 0)) as spend
    from {{ ref('stg_snapchat_ads__ad_stats') }}

),

fact_totals as (

    select
        platform,
        sum(spend) as spend
    from {{ ref('fct_marketing_ad_performance_daily') }}
    group by platform

)

select
    staging_totals.platform,
    staging_totals.spend as staging_spend,
    fact_totals.spend as fact_spend
from staging_totals
left join fact_totals
    on staging_totals.platform = fact_totals.platform
where abs(coalesce(fact_totals.spend, 0) - staging_totals.spend) > 0.01
