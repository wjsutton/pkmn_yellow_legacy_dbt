-- int_navigation_guide: Step-by-step navigation enriched with map info and exits
-- Query: SELECT * FROM intermediate.int_navigation_guide WHERE map_name = 'PLAYERS_HOUSE_2F' ORDER BY step_order

WITH waypoints AS (
    SELECT *
    FROM {{ ref('stg_nav_route_waypoints') }}
),

map_meta AS (
    SELECT *
    FROM {{ ref('stg_nav_map_metadata') }}
),

map_exits AS (
    SELECT
        from_map,
        STRING_AGG(
            warp_type || ' at (' || from_x || ',' || from_y || ') -> ' || to_map,
            '; '
            ORDER BY warp_type, from_y, from_x
        ) AS available_exits
    FROM {{ ref('stg_nav_map_warps') }}
    GROUP BY from_map
),

enriched AS (
    SELECT
        w.route_section,
        w.step_order,
        w.map_name,
        w.target_x,
        w.target_y,
        w.action,
        w.action_detail,
        w.expected_result,
        w.notes,
        m.width AS map_width,
        m.height AS map_height,
        m.area_type,
        m.parent_area,
        e.available_exits,
        LEAD(w.map_name) OVER (ORDER BY w.step_order) AS next_map,
        LEAD(w.action) OVER (ORDER BY w.step_order) AS next_action,
        LEAD(w.action_detail) OVER (ORDER BY w.step_order) AS next_action_detail
    FROM waypoints w
    LEFT JOIN map_meta m ON w.map_name = m.map_name
    LEFT JOIN map_exits e ON w.map_name = e.from_map
)

SELECT * FROM enriched
ORDER BY step_order
