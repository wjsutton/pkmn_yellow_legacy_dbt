SELECT 
    {{ dbt_utils.generate_surrogate_key(['peao.Encounter_Area','peao.Map']) }} as id,
    peao.encounter_area,
    peao.map,
    gro.game_order
FROM {{ source('yellow_legacy', 'pkmn_encounter_area_order') }} peao
LEFT JOIN {{ ref('stg_game_route_order') }} gro ON peao.Map = gro.map 