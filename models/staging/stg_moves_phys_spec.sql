SELECT 
    {{ dbt_utils.generate_surrogate_key(['Type']) }} as id,
    Type as type,
    "Stat used" as stat_used
FROM {{ source('yellow_legacy', 'moves_phys_spec') }} 