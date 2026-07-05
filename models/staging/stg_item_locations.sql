SELECT
    {{ dbt_utils.generate_surrogate_key(['l.map', 'l.item_const', 'l.source_type', 'l.x', 'l.y', 'l.quantity', 'l.notes']) }} as id,
    l.map,
    l.item_const,
    l.source_type,
    l.x,
    l.y,
    l.quantity,
    l.price,
    l.currency,
    l.notes,
    r.game_order,
    r.next_gym
FROM {{ source('yellow_legacy', 'item_locations') }} l
LEFT JOIN {{ ref('stg_game_route_order') }} r
    ON l.map = r.map
