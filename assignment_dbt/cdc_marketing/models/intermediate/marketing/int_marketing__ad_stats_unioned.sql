{{ config(materialized='ephemeral') }}

-- Platform normalisation: both platforms are brought to the SAME grain
-- (platform x ad x day) and the SAME columns before the union, so nothing
-- downstream needs to know how Facebook or Snapchat structure their data.
--
--   * Snapchat reports per country      -> summed to ad x day
--   * NULL impressions / clicks          -> 0 (platforms omit zero metrics)
--   * rows with no spend, impressions or clicks carry no information -> dropped
--   * currency: Facebook from the account, Snapchat from the stats row

with facebook_stats as (

    select * from {{ ref('stg_facebook_ads__ad_stats') }}

),

facebook_accounts as (

    select
        account_id,
        currency_code
    from {{ ref('stg_facebook_ads__accounts') }}
    qualify row_number() over (partition by account_id order by updated_at desc) = 1

),

snapchat_stats as (

    select * from {{ ref('stg_snapchat_ads__ad_stats') }}

),

facebook as (

    select
        'facebook' as platform,
        facebook_stats.ad_id,
        facebook_stats.date_day,
        facebook_accounts.currency_code,
        coalesce(facebook_stats.spend, 0) as spend,
        coalesce(facebook_stats.impressions, 0) as impressions,
        coalesce(facebook_stats.clicks, 0) as clicks

    from facebook_stats
    left join facebook_accounts
        on facebook_stats.account_id = facebook_accounts.account_id

),

snapchat as (

    select
        'snapchat' as platform,
        ad_id,
        date_day,
        max(currency_code) as currency_code,
        sum(coalesce(spend, 0)) as spend,
        sum(coalesce(impressions, 0)) as impressions,
        sum(coalesce(clicks, 0)) as clicks

    from snapchat_stats
    group by ad_id, date_day

),

unioned as (

    select * from facebook
    union all
    select * from snapchat

)

select * from unioned
where spend > 0 or impressions > 0 or clicks > 0
