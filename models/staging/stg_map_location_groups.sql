SELECT
    game_route_map,
    map_location
FROM {{ ref('map_location_groups') }}
