SELECT
    map_name,
    tileset_name
FROM {{ ref('nav_map_tileset') }}
