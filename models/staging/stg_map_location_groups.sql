SELECT
    game_route_map,
    map_location
FROM {{ source('yellow_legacy', 'map_location_groups') }}
