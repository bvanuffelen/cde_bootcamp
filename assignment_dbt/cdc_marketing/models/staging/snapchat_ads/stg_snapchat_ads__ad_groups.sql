-- Keeps ALL history versions (one row per ad group version). The current
-- version is selected in int_snapchat_ads__ads_enriched; doing it here would
-- hide the history from anyone who needs it later (e.g. for a snapshot).
with source as (

    select * from {{ source('snapchat_ads', 'ad_groups') }}

),

renamed as (

    select
        cast(_surrogate_key as string) as ad_group_version_id,
        cast(ad_group_id as string) as ad_group_id,
        cast(campaign_id as string) as campaign_id,
        cast(ad_group_name as string) as ad_group_name,
        cast(ad_group_updated_at as timestamp) as updated_at

    from source

)

select * from renamed
