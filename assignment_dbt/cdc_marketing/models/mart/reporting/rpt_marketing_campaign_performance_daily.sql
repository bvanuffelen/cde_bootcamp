-- The "one table to answer marketing questions" for BI tools and AI agents:
-- one row per platform x campaign x day, readable names, and the standard
-- KPIs already calculated. Rebuilt in full every run (table), so names are
-- always current; ~8k rows.

with performance as (

    select * from {{ ref('fct_marketing_ad_performance_daily') }}

),

campaigns as (

    select * from {{ ref('dim_marketing_campaigns') }}

),

campaign_day as (

    select
        campaign_key,
        platform,
        date_day,
        date_month,
        sum(spend_eur) as spend_eur,
        sum(impressions) as impressions,
        sum(clicks) as clicks,
        count(distinct ad_id) as active_ads

    from performance
    group by campaign_key, platform, date_day, date_month

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['campaign_day.campaign_key', 'campaign_day.date_day']) }}
            as campaign_performance_id,
        campaign_day.date_day,
        campaign_day.date_month,
        campaign_day.platform,
        campaign_day.campaign_key,
        campaigns.campaign_id,
        campaigns.campaign_name,
        campaigns.account_id,
        campaigns.account_name,

        campaign_day.spend_eur,
        campaign_day.impressions,
        campaign_day.clicks,
        campaign_day.active_ads,

        -- KPIs for THIS row. NULL (not 0, not an error) when the denominator
        -- is 0: a CPC of 0 would claim clicks were free.
        campaign_day.clicks / nullif(campaign_day.impressions, 0) as ctr,
        campaign_day.spend_eur / nullif(campaign_day.clicks, 0) as cpc_eur,
        campaign_day.spend_eur * 1000 / nullif(campaign_day.impressions, 0) as cpm_eur

    from campaign_day
    left join campaigns
        on campaign_day.campaign_key = campaigns.campaign_key

)

select * from final
