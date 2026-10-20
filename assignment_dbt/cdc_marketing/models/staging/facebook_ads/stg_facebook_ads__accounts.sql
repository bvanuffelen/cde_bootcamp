with source as (

    select * from {{ source('facebook_ads', 'accounts') }}

),

renamed as (

    select
        cast(account_id as string) as account_id,
        cast(account_name as string) as account_name,
        upper(cast(ad_currency_code as string)) as currency_code,
        cast(account_created_at as timestamp) as created_at,
        cast(account_updated_at as timestamp) as updated_at

    from source

)

select * from renamed
