SELECT
    pokedex,
    pokemon,
    catch_rate
FROM {{ ref('pkmn_catch_rates') }}
