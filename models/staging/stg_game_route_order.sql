SELECT 
    map,
    game_order,
    next_gym
FROM {{ source('yellow_legacy', 'game_route_order') }} 