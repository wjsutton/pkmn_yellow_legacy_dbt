WITH CTE AS (

    SELECT 
        "Attacking Type" as attacking_type,
        "Defending Type" as defending_type,
        "Damage Modifier" as damage_modifier
    FROM {{ source('yellow_legacy', 'moves_type_effectiveness') }} 

)

SELECT 
    {{ dbt_utils.generate_surrogate_key(['attacking_type','defending_type']) }} as id,
    attacking_type,
    defending_type,
    damage_modifier
FROM CTE