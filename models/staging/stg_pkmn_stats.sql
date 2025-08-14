SELECT 
    pokedex,
    pokemon,
    hp,
    attack,
    defense,
    special,
    speed,
    total,
    type1,
    type2
FROM {{ source('yellow_legacy', 'pkmn_stats') }} 