{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='ad_performance_id',
        on_schema_change='fail',
        cluster_by=['platform', 'date_day'],
        contract={'enforced': true}
    )
}}

{%- set lookback_days = var('marketing_lookback_days', 3) | int %}

-- Grain: one row per platform x ad x day.
-- Narrow on purpose: keys + additive metrics only. Names live in the dims
-- (and in rpt_marketing_campaign_performance_daily), so a campaign rename
-- never leaves stale names in old incremental rows.

with ad_stats as (

    select * from {{ ref('int_marketing__ad_stats_unioned') }}

),

ads as (

    select * from {{ ref('dim_marketing_ads') }}

),

fx_rates as (

    select * from {{ ref('fx_rates_annual') }}

),

{% if is_incremental() %}
    -- Watermark PER PLATFORM. Platforms deliver on their own schedules (in
    -- this data Snapchat ends a year before Facebook), so a single
    -- MAX(date_day) would silently skip a lagging platform. The lookback
    -- re-processes the last N days because ad platforms restate spend after
    -- the fact; MERGE on the unique key makes re-processing idempotent.
    watermarks as (

        select
            platform,
            cast(
                {{ dateadd('day', -1 * lookback_days, 'max(date_day)') }}
                as date
            ) as reprocess_from
        from {{ this }}
        group by platform

    ),
{% endif %}

filtered as (

    select ad_stats.*
    from ad_stats
    {% if is_incremental() %}
        left join watermarks
            on ad_stats.platform = watermarks.platform
        where
            watermarks.reprocess_from is null   -- platform not loaded yet
            or ad_stats.date_day >= watermarks.reprocess_from
    {% endif %}

),

final as (

    select
        cast(
            {{ dbt_utils.generate_surrogate_key(['filtered.platform', 'filtered.ad_id', 'filtered.date_day']) }}
            as string
        ) as ad_performance_id,

        cast(filtered.date_day as date) as date_day,
        cast(date_trunc('month', filtered.date_day) as date) as date_month,
        cast(filtered.platform as string) as platform,

        cast(ads.ad_key as string) as ad_key,
        cast(ads.campaign_key as string) as campaign_key,
        cast(filtered.ad_id as string) as ad_id,
        cast(ads.ad_group_id as string) as ad_group_id,
        cast(ads.campaign_id as string) as campaign_id,
        cast(ads.account_id as string) as account_id,

        cast(filtered.currency_code as string) as currency_code,
        cast(filtered.spend as decimal(18, 4)) as spend,
        cast(filtered.spend / fx_rates.units_per_eur as decimal(18, 4)) as spend_eur,
        cast(filtered.impressions as bigint) as impressions,
        cast(filtered.clicks as bigint) as clicks,

        cast(current_timestamp as timestamp) as dbt_updated_at

    from filtered
    left join ads
        on
            filtered.platform = ads.platform
            and filtered.ad_id = ads.ad_id
    left join fx_rates
        on
            year(filtered.date_day) = fx_rates.rate_year
            and filtered.currency_code = fx_rates.currency_code

)

select * from final
