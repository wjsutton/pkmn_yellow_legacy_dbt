SELECT 
    {{ dbt_utils.generate_surrogate_key(['Encounter_Area','Map']) }} as id,
    Encounter_Area as encounter_area,
    Map as map
FROM {{ source('yellow_legacy', 'pkmn_encounter_area_order') }} 