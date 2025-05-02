WITH CTE AS (

    SELECT DISTINCT
        "Pokedex Number" as pokedex,
        Pokemon as pokemon,
        Level as level,
        Move as move,
        Type as type,
        Power as power,
        Accuracy as accuracy,
        PP as pp
    FROM {{ source('yellow_legacy', 'moves_from_level_up') }} 

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['pokedex','level','move']) }} as id,
    pokemon,
    level,
    move,
    type,
    power,
    accuracy,
    pp
FROM CTE