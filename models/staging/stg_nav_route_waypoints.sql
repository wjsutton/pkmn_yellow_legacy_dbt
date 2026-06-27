SELECT
    route_section,
    CAST(step_order AS INTEGER) AS step_order,
    map_name,
    CAST(target_x AS INTEGER) AS target_x,
    CAST(target_y AS INTEGER) AS target_y,
    action,
    action_detail,
    expected_result,
    notes
FROM {{ source('yellow_legacy', 'nav_route_waypoints') }}
