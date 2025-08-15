SELECT 
    {{ dbt_utils.generate_surrogate_key(['Type']) }} as id,
    type,
    stat_used
FROM {{ source('yellow_legacy', 'moves_phys_spec') }} 