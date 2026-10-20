with source as (

    select * from {{ source('snapchat_ads', 'ad_stats') }}

),

renamed as (

    select
        -- keys (Snapchat calls the ad id "ad_detail_id")
        cast(ad_detail_id as string) as ad_id,

        -- dimensions
        cast(ad_date as date) as date_day,
        lower(cast(ad_country as string)) as country_code,
        upper(cast(ad_currency_code as string)) as currency_code,

        -- metrics (NULLs preserved, see stg_facebook_ads__ad_stats)
        try_cast(ad_spend as decimal(18, 6)) as spend,
        try_cast(ad_impressions as bigint) as impressions,
        try_cast(ad_clicks as bigint) as clicks,

        -- lineage
        _loaded_at

    from source

)

select * from renamed
