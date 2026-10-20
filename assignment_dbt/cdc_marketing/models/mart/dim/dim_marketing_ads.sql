-- One row per platform x ad. Full rebuild (table): ~100k rows, seconds to
-- build, and renamed ads/campaigns are always current.

with ads as (

    select * from {{ ref('int_facebook_ads__ads_enriched') }}
    union all
    select * from {{ ref('int_snapchat_ads__ads_enriched') }}

),

final as (

    select
        {{ dbt_utils.generate_surrogate_key(['platform', 'ad_id']) }} as ad_key,
        -- NULL (not a hash of NULL) when the campaign is unknown, so the
        -- relationship to dim_marketing_campaigns stays honest
        case
            when campaign_id is not null
                then {{ dbt_utils.generate_surrogate_key(['platform', 'campaign_id']) }}
        end as campaign_key,
        platform,
        ad_id,
        ad_name,
        ad_status,
        ad_group_id,
        ad_group_name,
        campaign_id,
        campaign_name,
        account_id,
        account_name

    from ads

)

select * from final
