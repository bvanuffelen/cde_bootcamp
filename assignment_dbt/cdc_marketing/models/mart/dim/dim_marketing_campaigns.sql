-- One row per platform x campaign, including campaigns that never spent.

with facebook_campaigns as (

    select * from {{ ref('stg_facebook_ads__campaigns') }}
    qualify row_number() over (partition by campaign_id order by updated_at desc) = 1

),

-- Facebook campaigns carry no account_id: derive it from their ads
-- (verified on the data: every campaign belongs to exactly one account).
facebook_campaign_accounts as (

    select
        campaign_id,
        max(account_id) as account_id,
        max(account_name) as account_name
    from {{ ref('int_facebook_ads__ads_enriched') }}
    group by campaign_id

),

snapchat_campaigns as (

    select * from {{ ref('stg_snapchat_ads__campaigns') }}

),

unioned as (

    select
        'facebook' as platform,
        facebook_campaigns.campaign_id,
        facebook_campaigns.campaign_name,
        facebook_campaign_accounts.account_id,
        facebook_campaign_accounts.account_name
    from facebook_campaigns
    left join facebook_campaign_accounts
        on facebook_campaigns.campaign_id = facebook_campaign_accounts.campaign_id

    union all

    select
        'snapchat' as platform,
        campaign_id,
        campaign_name,
        account_id,
        cast(null as string) as account_name
    from snapchat_campaigns

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['platform', 'campaign_id']) }} as campaign_key,
        platform,
        campaign_id,
        campaign_name,
        account_id,
        account_name
    from unioned

)

select * from final
