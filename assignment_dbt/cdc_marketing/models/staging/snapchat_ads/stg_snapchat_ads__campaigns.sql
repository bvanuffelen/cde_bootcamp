with source as (

    select * from {{ source('snapchat_ads', 'campaigns') }}

),

renamed as (

    select
        cast(campaign_id as string) as campaign_id,
        cast(account_id as string) as account_id,
        cast(campaign_name as string) as campaign_name

    from source

)

select * from renamed
