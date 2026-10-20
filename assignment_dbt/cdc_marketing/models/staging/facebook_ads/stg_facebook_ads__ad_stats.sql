with source as (

    select * from {{ source('facebook_ads', 'ad_stats') }}

),

renamed as (

    select
        -- keys: ids stay STRING, ~46% of Facebook ad ids exceed 2^53 and would
        -- be corrupted as DOUBLE
        cast(ad_id as string) as ad_id,
        cast(account_id as string) as account_id,

        -- date
        cast(ad_date as date) as date_day,

        -- metrics: try_cast turns the literal 'null' into NULL; NULLs are
        -- kept here (staging mirrors the source) and handled in intermediate
        try_cast(ad_spend as decimal(18, 6)) as spend,
        try_cast(ad_impressions as bigint) as impressions,
        try_cast(ad_clicks as bigint) as clicks,

        -- lineage
        _loaded_at

    from source

)

select * from renamed
