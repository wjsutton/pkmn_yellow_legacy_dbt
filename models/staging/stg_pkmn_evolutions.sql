SELECT 
    {{ dbt_utils.generate_surrogate_key(['pokedex','evolution_name']) }} as id,
    pokedex,
    CASE
        WHEN pokemon = 'Mr. Mime' THEN 'Mr-mime'
        ELSE pokemon
    END as pokemon,
    {{ species_key("CASE WHEN pokemon = 'Mr. Mime' THEN 'Mr-mime' ELSE pokemon END") }} AS species_key,
    evolution_level,
    evolution_stone,
    CASE
        WHEN evolution_name = 'Mr. Mime' THEN 'Mr-mime'
        ELSE evolution_name
    END as evolution_name,
    {{ species_key("CASE WHEN evolution_name = 'Mr. Mime' THEN 'Mr-mime' ELSE evolution_name END") }} AS evolution_key
FROM {{ ref('pkmn_evolutions') }} 