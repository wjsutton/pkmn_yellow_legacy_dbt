
WITH CTE AS (

    SELECT 
        Trainer as trainer,
        Pkmn_id as pkmn_id,
        Map as location,
        Nearest_Route as nearest_route,
        CASE Pokemon 
            WHEN 'Ratatta' THEN 'Rattata'
            WHEN 'Mr Mime' THEN 'Mr-mime'
            WHEN 'Weepingbell' THEN 'Weepinbell'
            ELSE Pokemon
        END as pokemon,
        Game_Stage as game_stage,
        Notes as notes,
        Level as level,
        CASE Moves 
            WHEN 'Poison Powder' THEN 'Poisonpowder'
            WHEN 'Double-Edge' THEN 'Double Edge'
            ELSE Moves
        END as move
    FROM {{ source('yellow_legacy', 'trainers_gym_leaders') }} 
    WHERE Moves IS NOT NULL

)

SELECT 
    {{ dbt_utils.generate_surrogate_key(['pkmn_id', 'move']) }} as id,
    trainer,
    pkmn_id,
    location,
    nearest_route,
    pokemon,
    game_stage,
    notes,
    level,
    move,
    ROW_NUMBER() OVER (PARTITION BY pkmn_id ORDER BY move) AS move_number
FROM CTE
QUALIFY ROW_NUMBER() OVER(PARTITION BY pkmn_id ORDER BY move) <= 4