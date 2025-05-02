WITH CTE AS (

    SELECT 
        "Pokedex Number" as pokedex,
        Pokemon as pokemon,
        Move as move
    FROM {{ source('yellow_legacy', 'moves_from_tmhm') }} 

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['pokedex','move']) }} as id,
    pokedex,
    pokemon,
    move
FROM CTE