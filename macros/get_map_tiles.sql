{% macro get_map_tiles(map_name) %}
-- Tile coordinates + walkability for {{ map_name }} (boundary / edge-warp detection).
SELECT x, y, walkable
FROM {{ ref('stg_nav_map_tiles') }}
WHERE map_name = '{{ map_name }}'
{% endmacro %}
