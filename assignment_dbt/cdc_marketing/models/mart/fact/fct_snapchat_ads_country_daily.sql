-- Snapchat is the only platform that reports by country. The unified fact
-- sums countries away; this model keeps them for country-level questions.
-- Table: ~3k rows, a full rebuild is cheaper than incremental bookkeeping.

with stats as (

    select * from {{ ref('stg_snapchat_ads__ad_stats') }}

),

ads as (

    select
        ad_key,
        campaign_key,
        ad_id
    from {{ ref('dim_marketing_ads') }}
    where platform = 'snapchat'

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['stats.ad_id', 'stats.date_day', 'stats.country_code']) }}
            as snapchat_country_performance_id,
        stats.date_day,
        stats.country_code,
        ads.ad_key,
        ads.campaign_key,
        stats.ad_id,
        stats.currency_code,
        coalesce(stats.spend, 0) as spend,
        coalesce(stats.impressions, 0) as impressions,
        coalesce(stats.clicks, 0) as clicks

    from stats
    left join ads
        on stats.ad_id = ads.ad_id

)

select * from final
