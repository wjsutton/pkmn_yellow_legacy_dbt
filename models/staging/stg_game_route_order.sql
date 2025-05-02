SELECT 
    Map as map,
    "Order" as order,
    "Next Gym" as next_gym
FROM {{ source('yellow_legacy', 'game_route_order') }} 