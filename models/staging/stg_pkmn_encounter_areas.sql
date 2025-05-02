SELECT 
    {{ dbt_utils.generate_surrogate_key(['Map','Level','Pokemon','Area']) }} as id,
    Map as map,
    Level as level,
    Pokemon as pokemon,
    Area as area,
    SUM("Encounter Probability") as encounter_probability
FROM {{ source('yellow_legacy', 'pkmn_encounter_areas') }}
GROUP BY ALL