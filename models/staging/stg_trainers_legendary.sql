
SELECT 
    {{ dbt_utils.generate_surrogate_key(['Pkmn_id', 'Moves']) }} as id,
    Trainer as trainer,
    Pkmn_id as pkmn_id,
    Map as location,
    Nearest_Route as nearest_route,
    Pokemon as pokemon,
    Game_Stage as game_stage,
    NULL as notes,
    Level as level,
    Moves as move,
    ROW_NUMBER() OVER (PARTITION BY Pkmn_id ORDER BY Moves) AS move_number
FROM {{ source('yellow_legacy', 'trainers_legendary') }} 
WHERE Moves IS NOT NULL
