-- Facebook calls ad groups "ad sets"; the unified vocabulary uses ad_group_*.
with source as (

    select * from {{ source('facebook_ads', 'ad_sets') }}

),

renamed as (

    select
        cast(ad_group_id as string) as ad_group_id,
        cast(ad_group_name as string) as ad_group_name,
        cast(ad_group_updated_at as timestamp) as updated_at

    from source

)

select * from renamed
