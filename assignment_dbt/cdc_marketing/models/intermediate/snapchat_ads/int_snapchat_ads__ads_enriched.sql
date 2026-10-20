-- One row per Snapchat ad with its full hierarchy flattened, in exactly the
-- same column set as int_facebook_ads__ads_enriched.
-- Snapchat ads do not reference their campaign directly: the path is
-- ad -> ad group -> campaign -> account.

with ads as (

    select * from {{ ref('stg_snapchat_ads__ads') }}
    qualify row_number() over (partition by ad_id order by updated_at desc) = 1

),

-- The ad group export is a history table: 3 ad groups have 2 versions.
-- Joining without this step would double those ads' spend.
ad_groups as (

    select * from {{ ref('stg_snapchat_ads__ad_groups') }}
    qualify row_number() over (partition by ad_group_id order by updated_at desc) = 1

),

campaigns as (

    select * from {{ ref('stg_snapchat_ads__campaigns') }}

),

joined as (

    select
        'snapchat' as platform,
        ads.ad_id,
        ads.ad_name,
        cast(null as string) as ad_status,       -- not in the Snapchat export
        ads.ad_group_id,
        ad_groups.ad_group_name,
        ad_groups.campaign_id,
        campaigns.campaign_name,
        campaigns.account_id,
        cast(null as string) as account_name     -- no account table exported

    from ads
    left join ad_groups
        on ads.ad_group_id = ad_groups.ad_group_id
    left join campaigns
        on ad_groups.campaign_id = campaigns.campaign_id

)

select * from joined
