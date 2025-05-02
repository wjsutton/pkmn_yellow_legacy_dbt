SELECT 
    {{ dbt_utils.generate_surrogate_key(['Move']) }} as id,
    Move as move,
    Effect as effect,
    Type as type,
    Power as power,
    Acc as acc,
    PP as pp,
    Hits as hits,
    "Hits Min" as hits_min,
    "Hits Max" as hits_max,
    "Critical-hit Ratio" as critical_hit_ratio
FROM {{ source('yellow_legacy', 'moves_stats') }} 