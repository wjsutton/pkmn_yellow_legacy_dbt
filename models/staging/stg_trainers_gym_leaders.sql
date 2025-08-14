
WITH CTE AS (

    SELECT 
        trainer,
        pkmn_id,
        map as location,
        nearest_route,
        CASE pokemon 
            WHEN 'Ratatta' THEN 'Rattata'
            WHEN 'Mr Mime' THEN 'Mr-mime'
            WHEN 'Weepingbell' THEN 'Weepinbell'
            ELSE pokemon
        END as pokemon,
        game_stage,
        notes,
        pkmn_level,
        CASE moves 
            WHEN 'Poison Powder' THEN 'Poisonpowder'
            WHEN 'Double-Edge' THEN 'Double Edge'
            ELSE moves
        END as move
    FROM {{ source('yellow_legacy', 'trainers_gym_leaders') }} 
    WHERE moves IS NOT NULL

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
    pkmn_level,
    move,
    ROW_NUMBER() OVER (PARTITION BY pkmn_id ORDER BY move) AS move_number
FROM CTE
QUALIFY ROW_NUMBER() OVER(PARTITION BY pkmn_id ORDER BY move) <= 4