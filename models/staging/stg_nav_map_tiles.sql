SELECT
    map_name,
    CAST(x AS INTEGER) AS x,
    CAST(y AS INTEGER) AS y,
    tile_type,
    CASE WHEN walkable = 'True' THEN TRUE ELSE FALSE END AS walkable,
    COALESCE(NULLIF(ledge_direction, ''), NULL) AS ledge_direction
FROM {{ ref('nav_map_tiles') }}
