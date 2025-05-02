SELECT 
    "TM/HM" as tm_or_hm,
    Move as move,
    Type as type,
    Locations as locations,
    Price as price,
    "Earliest Nearest Route" as earliest_nearest_route,
    "Repurchase Route" as repurchase_route
FROM {{ source('yellow_legacy', 'moves_tmhm_locations') }} 