
SELECT 
    {{ dbt_utils.generate_surrogate_key(['pkmn_id', 'moves']) }} as id,
    trainer,
    pkmn_id,
    map as location,
    nearest_route,
    pokemon,
    game_stage,
    NULL as notes,
    pkmn_level,
    moves as move,
    ROW_NUMBER() OVER (PARTITION BY pkmn_id ORDER BY moves) AS move_number
FROM {{ source('yellow_legacy', 'trainers_legendary') }} 
WHERE moves IS NOT NULL
