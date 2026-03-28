SELECT
    {{ dbt_utils.generate_surrogate_key(['map','level','pokemon','area']) }} as id,
    map,
    COALESCE(level, 24) as level,
    pokemon,
    area,
    SUM(encounter_probability) as encounter_probability,
    MAX(available_from_order) as available_from_order
FROM {{ source('yellow_legacy', 'pkmn_encounter_areas') }}
GROUP BY ALL
