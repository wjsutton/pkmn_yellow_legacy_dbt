SELECT 
    pokedex as pokedex,
    pokemon as pokemon,
    HP as hp,
    Attack as attack,
    Defense as defense,
    Special as special,
    Speed as speed,
    Total as total,
    Type1 as type1,
    Type2 as type2
FROM {{ source('yellow_legacy', 'pkmn_stats') }} 