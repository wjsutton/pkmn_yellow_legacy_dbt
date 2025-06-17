SELECT 
    x as x,
    y as y,
    type as location_type,
    map as map,
    "display name" as display_name
FROM {{ source('yellow_legacy', 'map_locations') }} 