-- One row per Facebook ad with its full hierarchy flattened.
-- The exports contain one row per id today, but they are history-style
-- tables (they carry updated_at), so the latest version is selected
-- defensively - a second version arriving tomorrow cannot fan out the joins.

with ads as (

    select * from {{ ref('stg_facebook_ads__ads') }}
    qualify row_number() over (partition by ad_id order by updated_at desc) = 1

),

ad_sets as (

    select * from {{ ref('stg_facebook_ads__ad_sets') }}
    qualify row_number() over (partition by ad_group_id order by updated_at desc) = 1

),

campaigns as (

    select * from {{ ref('stg_facebook_ads__campaigns') }}
    qualify row_number() over (partition by campaign_id order by updated_at desc) = 1

),

accounts as (

    select * from {{ ref('stg_facebook_ads__accounts') }}
    qualify row_number() over (partition by account_id order by updated_at desc) = 1

),

joined as (

    select
        'facebook' as platform,
        ads.ad_id,
        ads.ad_name,
        ads.ad_status,
        ads.ad_group_id,
        ad_sets.ad_group_name,
        ads.campaign_id,
        campaigns.campaign_name,
        ads.account_id,
        accounts.account_name

    from ads
    left join ad_sets
        on ads.ad_group_id = ad_sets.ad_group_id
    left join campaigns
        on ads.campaign_id = campaigns.campaign_id
    left join accounts
        on ads.account_id = accounts.account_id

)

select * from joined
