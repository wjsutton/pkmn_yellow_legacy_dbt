SELECT 
    "TM/HM" as tm_or_hm,
    CASE 
        WHEN Move = 'BubbleBeam' THEN 'Bubblebeam'
        WHEN Move = 'SolarBeam' THEN 'Solarbeam'  
        WHEN Move = 'Double-Edge' THEN 'Double Edge'
        ELSE Move 
    END as move,
    Type as type,
    Locations as locations,
    Price as price,
    "Earliest Nearest Route" as earliest_nearest_route,
    COALESCE("Repurchase Route", "Earliest Nearest Route") as repurchase_route
FROM {{ source('yellow_legacy', 'moves_tmhm_locations') }} 