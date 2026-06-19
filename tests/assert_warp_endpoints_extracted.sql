-- Test: every warp endpoint map must exist in the extracted tile data.
-- Catches name mismatches / un-extracted maps (the kind that produced the old
-- ROUTE_2_HOUSE and PEWTER_MUSEUM_1F warps pointing at maps with zero tiles).
WITH maps AS (
    SELECT DISTINCT map_name FROM {{ ref('stg_nav_map_tiles') }}
),
endpoints AS (
    SELECT from_map AS map_name FROM {{ ref('stg_nav_map_warps') }}
    UNION
    SELECT to_map FROM {{ ref('stg_nav_map_warps') }}
)
SELECT e.map_name AS missing_map
FROM endpoints e
LEFT JOIN maps m ON e.map_name = m.map_name
WHERE m.map_name IS NULL
