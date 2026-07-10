SELECT 
    {{ dbt_utils.generate_surrogate_key(['Type']) }} as id,
    type,
    stat_used
FROM {{ ref('moves_phys_spec') }} 