{% macro get_grass_tiles(map_name) %}
-- Grass tile coordinates on {{ map_name }} (wild-encounter seeking).
SELECT x, y
FROM {{ ref('stg_nav_map_tiles') }}
WHERE map_name = '{{ map_name }}' AND tile_type = 'grass'
ORDER BY x, y
{% endmacro %}
