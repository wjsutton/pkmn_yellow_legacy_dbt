SELECT 
    map,
    game_order,
    next_gym
FROM {{ ref('game_route_order') }} 