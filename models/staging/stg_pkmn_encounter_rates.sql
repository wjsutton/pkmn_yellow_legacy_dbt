SELECT
    map,
    grass_rate,
    water_rate
FROM {{ ref('pkmn_encounter_rates') }}
