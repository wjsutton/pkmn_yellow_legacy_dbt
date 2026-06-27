{% macro get_map_edges(map_name) %}
-- Walkable adjacency edges for BFS pathfinding on {{ map_name }}.
SELECT from_x, from_y, to_x, to_y, direction
FROM {{ ref('int_map_pathfinding') }}
WHERE map_name = '{{ map_name }}'
{% endmacro %}
