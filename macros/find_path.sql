{% macro find_path(map_name, start_x, start_y, target_x, target_y, max_steps=50, avoid_grass=false, blocked_coordinates='') %}
-- BFS shortest path from ({{ start_x }}, {{ start_y }}) to ({{ target_x }}, {{ target_y }}) on {{ map_name }}
WITH RECURSIVE bfs AS (
    SELECT
        {{ start_x }} AS x,
        {{ start_y }} AS y,
        0 AS steps,
        CAST([] AS VARCHAR[]) AS path,
        [{{ start_y }} * 1000 + {{ start_x }}] AS visited,
        0 AS grass_count

    UNION ALL

    SELECT
        pf.to_x,
        pf.to_y,
        b.steps + 1,
        list_append(b.path, pf.direction),
        list_append(b.visited, pf.to_y * 1000 + pf.to_x),
        b.grass_count + CASE WHEN pf.has_encounter_risk THEN 1 ELSE 0 END
    FROM bfs b
    INNER JOIN {{ ref('int_map_pathfinding') }} pf
        ON pf.map_name = '{{ map_name }}'
        AND pf.from_x = b.x
        AND pf.from_y = b.y
        AND NOT list_contains(b.visited, pf.to_y * 1000 + pf.to_x)
    WHERE b.steps < {{ max_steps }}
        AND NOT (b.x = {{ target_x }} AND b.y = {{ target_y }})
        {% if blocked_coordinates != '' %}
        AND {{ blocked_coordinates }}
        {% endif %}
)
SELECT steps, path, grass_count
FROM bfs
WHERE x = {{ target_x }} AND y = {{ target_y }}
ORDER BY steps{% if avoid_grass %}, grass_count{% endif %}

LIMIT 1
{% endmacro %}
