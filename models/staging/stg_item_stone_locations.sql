SELECT
    {{ dbt_utils.generate_surrogate_key(['s.stone_type', 's.map', 's.source_type']) }} as id,
    s.stone_type,
    s.map,
    s.quantity,
    s.source_type,
    r.game_order,
    r.next_gym
FROM {{ source('yellow_legacy', 'item_stone_locations') }} s
LEFT JOIN {{ ref('stg_game_route_order') }} r
    ON s.map = r.map
