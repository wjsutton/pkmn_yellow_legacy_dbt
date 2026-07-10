-- int_map_pathfinding: Walkable tile adjacency graph per map
-- For each walkable tile, lists which neighboring tiles can be reached and in which direction.
-- Accounts for walls (blocked), ledges (one-way), and grass (encounter risk).
--
-- Query examples:
--   SELECT * FROM intermediate.int_map_pathfinding WHERE map_name = 'ROUTE_1' AND from_x = 5 AND from_y = 10
--   SELECT * FROM intermediate.int_map_pathfinding WHERE map_name = 'ROUTE_1' AND to_y = 0 ORDER BY from_y

WITH tiles AS (
    SELECT *
    FROM {{ ref('stg_nav_map_tiles') }}
),

-- Generate all possible movement edges (4 cardinal directions)
edges AS (
    SELECT
        src.map_name,
        src.x AS from_x,
        src.y AS from_y,
        src.tile_type AS from_tile_type,
        dst.x AS to_x,
        dst.y AS to_y,
        dst.tile_type AS to_tile_type,
        dst.ledge_direction,
        CASE
            WHEN dst.x = src.x AND dst.y = src.y - 1 THEN 'up'
            WHEN dst.x = src.x AND dst.y = src.y + 1 THEN 'down'
            WHEN dst.x = src.x - 1 AND dst.y = src.y THEN 'left'
            WHEN dst.x = src.x + 1 AND dst.y = src.y THEN 'right'
        END AS direction
    FROM tiles src
    JOIN tiles dst
        ON src.map_name = dst.map_name
        AND src.walkable = TRUE
        AND dst.walkable = TRUE
        AND (
            (dst.x = src.x AND dst.y = src.y - 1) OR  -- up
            (dst.x = src.x AND dst.y = src.y + 1) OR  -- down
            (dst.x = src.x - 1 AND dst.y = src.y) OR  -- left
            (dst.x = src.x + 1 AND dst.y = src.y)      -- right
        )
)

SELECT
    map_name,
    from_x,
    from_y,
    from_tile_type,
    to_x,
    to_y,
    to_tile_type,
    direction,
    -- Flag if destination has wild encounter risk
    to_tile_type = 'grass' AS has_encounter_risk
FROM edges
WHERE
    -- Filter out ledge entries that aren't passable from this direction
    (to_tile_type != 'ledge' OR ledge_direction = direction)
ORDER BY map_name, from_y, from_x, direction
