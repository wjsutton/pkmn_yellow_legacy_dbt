-- int_map_connections: Map-to-map connection reference with navigation instructions
-- Query: SELECT * FROM intermediate.int_map_connections WHERE from_map = 'VIRIDIAN_CITY'

WITH warps AS (
    SELECT *
    FROM {{ ref('stg_nav_map_warps') }}
),

map_meta AS (
    SELECT *
    FROM {{ ref('stg_nav_map_metadata') }}
),

components AS (
    SELECT *
    FROM {{ ref('int_map_components') }}
)

SELECT
    w.id,
    w.from_map,
    w.from_x,
    w.from_y,
    w.to_map,
    w.to_x,
    w.to_y,
    w.warp_type,
    w.notes,
    sm.width AS from_map_width,
    sm.height AS from_map_height,
    sm.area_type AS from_area_type,
    dm.width AS to_map_width,
    dm.height AS to_map_height,
    dm.area_type AS to_area_type,
    -- sub-region of the exit tile: warps in different sub-regions of the same
    -- map are unreachable from one another (e.g. ROUTE_2 north vs south)
    fc.subregion_id AS from_subregion_id,
    tc.subregion_id AS to_subregion_id,
    CASE
        WHEN w.warp_type = 'edge' THEN 'Walk to map edge (y=' || w.from_y || ') to transition'
        WHEN w.warp_type = 'stairs' THEN 'Walk to (' || w.from_x || ',' || w.from_y || ') to use stairs'
        WHEN w.warp_type = 'door' THEN 'Walk to (' || w.from_x || ',' || w.from_y || ') and press UP to enter door'
        WHEN w.warp_type = 'gate' THEN 'Walk to (' || w.from_x || ',' || w.from_y || ') to pass through gate'
        ELSE 'Navigate to (' || w.from_x || ',' || w.from_y || ')'
    END AS navigation_instruction
FROM warps w
LEFT JOIN map_meta sm ON w.from_map = sm.map_name
LEFT JOIN map_meta dm ON w.to_map = dm.map_name
LEFT JOIN components fc ON fc.map_name = w.from_map AND fc.x = w.from_x AND fc.y = w.from_y
LEFT JOIN components tc ON tc.map_name = w.to_map AND tc.x = w.to_x AND tc.y = w.to_y
ORDER BY w.from_map, w.warp_type, w.from_y, w.from_x
