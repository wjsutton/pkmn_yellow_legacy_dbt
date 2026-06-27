SELECT 
    pokedex,
    pokemon,
    growth_rate
FROM {{ ref('pkmn_growth_rates') }}
