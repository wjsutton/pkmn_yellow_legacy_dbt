SELECT 
    {{ dbt_utils.generate_surrogate_key(['pokedex','Evolution_name']) }} as id,
    pokedex as pokedex,
    pokemon as pokemon,
    "Evolution level" as evolution_level,
    Evolution_stone as evolution_stone,
    Evolution_name as evolution_name
FROM {{ source('yellow_legacy', 'pkmn_evolutions') }} 