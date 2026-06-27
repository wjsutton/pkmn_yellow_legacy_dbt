SELECT
    map_name,
    tileset_name
FROM {{ source('yellow_legacy', 'nav_map_tileset') }}
