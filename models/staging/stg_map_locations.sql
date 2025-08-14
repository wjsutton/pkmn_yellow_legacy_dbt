SELECT 
    x as x_coordinate,
    y as y_coordinate,
    type as location_type,
    COALESCE(map, 'MapCorner_' || CAST(x as VARCHAR) || '_' || CAST(y as VARCHAR)) as map,
    "display name" as display_name
FROM {{ source('yellow_legacy', 'map_locations') }} 