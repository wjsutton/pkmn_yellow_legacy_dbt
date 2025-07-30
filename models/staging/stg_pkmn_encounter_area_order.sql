SELECT 
    {{ dbt_utils.generate_surrogate_key(['peao.Encounter_Area','peao.Map']) }} as id,
    peao.Encounter_Area as encounter_area,
    peao.Map as map,
    gro."order" as "order"
FROM {{ source('yellow_legacy', 'pkmn_encounter_area_order') }} peao
LEFT JOIN {{ ref('stg_game_route_order') }} gro ON peao.Map = gro.map 