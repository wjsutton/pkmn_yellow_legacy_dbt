WITH CTE AS (

    SELECT 
        pokedex,
        pokemon,
        move
    FROM {{ source('yellow_legacy', 'moves_from_tmhm') }} 

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['pokedex','move']) }} as id,
    pokedex,
    pokemon,
    move
FROM CTE