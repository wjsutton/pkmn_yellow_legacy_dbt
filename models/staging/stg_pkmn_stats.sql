SELECT 
    pokedex,
    pokemon,
    hp,
    attack,
    defense as defence,
    special,
    speed,
    total,
    type1,
    type2
FROM {{ source('yellow_legacy', 'pkmn_stats') }} 