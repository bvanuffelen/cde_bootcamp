with source as (

    select * from {{ source('facebook_ads', 'ads') }}

),

renamed as (

    select
        cast(ad_id as string) as ad_id,
        cast(ad_group_id as string) as ad_group_id,
        cast(campaign_id as string) as campaign_id,
        cast(account_id as string) as account_id,
        cast(ad_name as string) as ad_name,
        upper(cast(ad_status as string)) as ad_status,
        cast(ad_updated_at as timestamp) as updated_at

    from source

)

select * from renamed
