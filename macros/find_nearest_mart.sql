{% macro find_nearest_mart(current_map, badge_count=0) %}
{#
  Find the nearest Poke Mart from any map using BFS across map connections.

  Parameters:
    current_map  - Current map in UPPER_SNAKE_CASE (e.g. 'VIRIDIAN_CITY')
    badge_count  - Number of badges (reserved for future badge-gated filtering)

  Returns up to 3 rows sorted by hops:
    mart_map    - Mart map name (e.g. VIRIDIAN_MART)
    parent_city - City the mart is in (e.g. VIRIDIAN_CITY)
    hops        - Number of map transitions to reach the mart
    path        - Array of map names in the route
    next_map    - First map to navigate toward (immediate next hop)

  Usage:
    {{ find_nearest_mart('ROUTE_1') }}
    {{ find_nearest_mart('CERULEAN_CITY', badge_count=2) }}
#}

WITH RECURSIVE mart_search AS (
    -- Base case: start from current map
    SELECT
        '{{ current_map }}' AS current_map,
        0 AS hops,
        CAST(['{{ current_map }}'] AS VARCHAR[]) AS path

    UNION ALL

    -- Recursive: expand to connected maps (stop expanding from mart nodes)
    SELECT
        c.to_map AS current_map,
        ms.hops + 1,
        list_append(ms.path, c.to_map)
    FROM mart_search ms
    INNER JOIN {{ ref('int_map_connections') }} c
        ON c.from_map = ms.current_map
        AND NOT list_contains(ms.path, c.to_map)
    WHERE ms.hops < 15
      AND NOT ms.current_map LIKE '%\_MART%' ESCAPE '\'
),

mart_results AS (
    SELECT
        ms.current_map AS mart_map,
        m.parent_area AS parent_city,
        ms.hops,
        ms.path,
        CASE
            WHEN ms.hops = 0 THEN ms.current_map
            ELSE ms.path[2]
        END AS next_map
    FROM mart_search ms
    INNER JOIN {{ ref('stg_nav_map_metadata') }} m
        ON m.map_name = ms.current_map
    WHERE ms.current_map LIKE '%\_MART%' ESCAPE '\'
)

SELECT *
FROM mart_results
ORDER BY hops
LIMIT 3

{% endmacro %}
