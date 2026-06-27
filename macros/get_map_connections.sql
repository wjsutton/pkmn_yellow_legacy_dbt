{% macro get_map_connections() %}
-- Full map-to-map adjacency list (BFS to nearest mart / multi-hop navigation).
SELECT DISTINCT from_map, to_map
FROM {{ ref('int_map_connections') }}
{% endmacro %}
