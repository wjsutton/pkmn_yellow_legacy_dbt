SELECT 
    {{ dbt_utils.generate_surrogate_key(['Move']) }} as id,
    move,
    effect,
    type,
    power,
    acc,
    pp,
    hits,
    hits_min,
    hits_max,
    critical_hit_ratio
FROM {{ ref('moves_stats') }} 