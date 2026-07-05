SELECT
    pokedex,
    pokemon,
    {{ species_key('pokemon') }} AS species_key,
    catch_rate
FROM {{ ref('pkmn_catch_rates') }}
