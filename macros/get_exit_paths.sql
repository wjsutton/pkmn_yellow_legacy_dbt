{% macro get_exit_paths(map_name, x, y) %}
-- Available exits from {{ map_name }} relative to player at ({{ x }}, {{ y }})
SELECT
    w.to_map,
    w.from_x AS exit_x,
    w.from_y AS exit_y,
    w.warp_type,
    w.notes AS description,
    ABS(w.from_x - {{ x }}) + ABS(w.from_y - {{ y }}) AS distance,
    CASE
        WHEN w.warp_type = 'stairs' THEN NULL
        WHEN w.warp_type = 'edge' THEN NULL
        WHEN w.from_y >= (m.height * 2 - 1) THEN 'down'
        WHEN w.from_y = 0 THEN 'up'
        WHEN w.from_x = 0 THEN 'left'
        WHEN w.from_x >= (m.width * 2 - 1) THEN 'right'
        WHEN w.warp_type = 'door' AND m.area_type IN ('town', 'city', 'route', 'dungeon') THEN 'up'
        WHEN w.warp_type = 'door' AND m.area_type = 'indoor' THEN 'down'
        WHEN w.warp_type = 'gate' AND w.from_y > m.height THEN 'down'
        WHEN w.warp_type = 'gate' AND w.from_y <= 1 THEN 'up'
        ELSE 'down'
    END AS required_facing
FROM {{ ref('stg_nav_map_warps') }} w
LEFT JOIN {{ ref('stg_nav_map_metadata') }} m ON w.from_map = m.map_name
WHERE w.from_map = '{{ map_name }}'
ORDER BY distance
{% endmacro %}
