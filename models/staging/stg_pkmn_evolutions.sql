SELECT 
    {{ dbt_utils.generate_surrogate_key(['pokedex','Evolution_name']) }} as id,
    pokedex as pokedex,
    CASE 
        WHEN pokemon = 'Mr. Mime' THEN 'Mr-mime'
        ELSE pokemon 
    END as pokemon,
    "Evolution level" as evolution_level,
    Evolution_stone as evolution_stone,
    CASE 
        WHEN Evolution_name = 'Mr. Mime' THEN 'Mr-mime'
        ELSE Evolution_name 
    END as evolution_name
FROM {{ source('yellow_legacy', 'pkmn_evolutions') }} 