SELECT 
    {{ dbt_utils.generate_surrogate_key(['map','level','pokemon','area']) }} as id,
    map,
    COALESCE(level, 25) as level,  -- Default level for trades/gifts
    pokemon,
    area,
    SUM(encounter_probability) as encounter_probability
FROM {{ source('yellow_legacy', 'pkmn_encounter_areas') }}
GROUP BY ALL