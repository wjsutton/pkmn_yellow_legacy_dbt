SELECT
    {{ dbt_utils.generate_surrogate_key(['from_map', 'from_x', 'from_y', 'to_map']) }} AS id,
    from_map,
    CAST(from_x AS INTEGER) AS from_x,
    CAST(from_y AS INTEGER) AS from_y,
    to_map,
    CAST(to_x AS INTEGER) AS to_x,
    CAST(to_y AS INTEGER) AS to_y,
    warp_type,
    notes
FROM {{ ref('nav_map_warps') }}
