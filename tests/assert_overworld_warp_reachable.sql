-- Test: every overworld (non-indoor) warp must be reachable on foot.
-- A warp group (from_map -> to_map) passes if ANY of its from-tiles is reachable:
--   * the from-tile itself is walkable, or a walkable orthogonal neighbour exists; or
--   * (edge warps) the named boundary row/column has a walkable tile.
-- Catches garbage/wrong warp coordinates -- e.g. the original ROUTE_2 (4,0)->PEWTER
-- edge that pointed at a wall column instead of the walkable (8,0)/(9,0) top edge.
--
-- Interior special-tile warps (elevators, multi-floor stairs, gym-exit doors) are
-- excluded: their warp tiles are steppable in-game but read as `wall` in the ROM
-- collision extraction, so they would false-fail. That interior coverage gap is a
-- separate, lower-priority tile-extraction issue and only affects late-game maps.
WITH conn AS (
    SELECT from_map, to_map, warp_type, from_x, from_y,
           from_map_width, from_map_height
    FROM {{ ref('int_map_connections') }}
    WHERE from_area_type <> 'indoor'
),
reach AS (
    SELECT cn.from_map, cn.to_map,
        CASE WHEN cn.warp_type = 'edge' THEN EXISTS (
            SELECT 1 FROM {{ ref('stg_nav_map_tiles') }} t
            WHERE t.map_name = cn.from_map AND t.walkable AND (
                (cn.from_y = 0 AND t.y = 0)
                OR (cn.from_y = cn.from_map_height - 1 AND t.y = cn.from_map_height - 1)
                OR (cn.from_x = 0 AND t.x = 0)
                OR (cn.from_x = cn.from_map_width - 1 AND t.x = cn.from_map_width - 1)))
        ELSE EXISTS (
            SELECT 1 FROM {{ ref('stg_nav_map_tiles') }} t
            WHERE t.map_name = cn.from_map AND t.walkable AND (
                (t.x = cn.from_x AND t.y = cn.from_y)
                OR (t.x = cn.from_x AND ABS(t.y - cn.from_y) = 1)
                OR (t.y = cn.from_y AND ABS(t.x - cn.from_x) = 1)))
        END AS reachable
    FROM conn cn
)
SELECT from_map, to_map
FROM reach
GROUP BY from_map, to_map
HAVING BOOL_OR(reachable) = FALSE
