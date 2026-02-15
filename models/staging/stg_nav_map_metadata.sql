SELECT
    map_name,
    map_id_hex,
    CAST(width AS INTEGER) AS width,
    CAST(height AS INTEGER) AS height,
    area_type,
    parent_area
FROM {{ source('yellow_legacy', 'nav_map_metadata') }}
