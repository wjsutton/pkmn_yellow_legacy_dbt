SELECT 
    {{ dbt_utils.generate_surrogate_key(['map','pkmn_level','pokemon','area']) }} as id,
    map,
    COALESCE(pkmn_level, 24) as pkmn_level,
    pokemon,
    area,
    SUM(encounter_probability) as encounter_probability
FROM {{ source('yellow_legacy', 'pkmn_encounter_areas') }}
GROUP BY ALL