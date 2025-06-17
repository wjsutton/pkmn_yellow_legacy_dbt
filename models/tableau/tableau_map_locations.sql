SELECT 
    M.*,
    G.order,
    G.next_gym as game_stage
FROM {{ ref('stg_map_locations')}} as M
LEFT JOIN {{ ref('stg_game_route_order')}} as G on M.map = G.map
