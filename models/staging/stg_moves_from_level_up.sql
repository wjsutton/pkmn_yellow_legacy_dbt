WITH CTE AS (

    SELECT DISTINCT
        pokedex,
        pokemon,
        pkmn_level,
        move,
        type,
        power,
        accuracy,
        pp
    FROM {{ source('yellow_legacy', 'moves_from_level_up') }} 

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['pokedex','pkmn_level','move']) }} as id,
    pokemon,
    pkmn_level,
    move,
    type,
    power,
    accuracy,
    pp
FROM CTE