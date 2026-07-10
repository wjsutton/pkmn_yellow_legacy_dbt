SELECT 
    tm_or_hm,
    CASE 
        WHEN move = 'BubbleBeam' THEN 'Bubblebeam'
        WHEN move = 'SolarBeam' THEN 'Solarbeam'  
        WHEN move = 'Double-Edge' THEN 'Double Edge'
        ELSE move 
    END as move,
    type,
    locations,
    price,
    earliest_nearest_route,
    COALESCE(repurchase_route, earliest_nearest_route) as repurchase_route
FROM {{ ref('moves_tmhm_locations') }} 