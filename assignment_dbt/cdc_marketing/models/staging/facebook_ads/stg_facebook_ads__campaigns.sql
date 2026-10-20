with source as (

    select * from {{ source('facebook_ads', 'campaigns') }}

),

renamed as (

    select
        cast(campaign_id as string) as campaign_id,
        cast(campaign_name as string) as campaign_name,
        cast(campaign_updated_at as timestamp) as updated_at

    from source

)

select * from renamed
