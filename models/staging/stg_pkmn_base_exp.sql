SELECT 
    pokedex,
    pokemon,
    base_exp
FROM {{ ref('pkmn_base_exp') }}
