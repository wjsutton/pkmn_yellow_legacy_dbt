SELECT
    pokedex,
    pokemon,
    {{ species_key('pokemon') }} AS species_key,
    hp,
    attack,
    defense as defence,
    special,
    speed,
    total,
    type1,
    type2
FROM {{ ref('pkmn_stats') }} 