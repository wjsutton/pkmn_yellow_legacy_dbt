WITH mandatory_trainers_with_moves AS (

	SELECT
        T.trainer,
        T.pkmn_id,
        T.nearest_route,
        T.pokemon,
        T.game_stage,
        T.notes,
        T.level,
        M.move
    FROM {{ ref('stg_trainers_mandatory') }} as T
	LEFT JOIN {{ ref('stg_moves_from_level_up') }} as M on T.pokemon = M.pokemon
	WHERE T.level >= M.level

)

, all_trainers AS (

    SELECT 
        trainer,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        'Legendary' as notes,
        level,
        move,
        move_number
    FROM {{ ref('stg_trainers_legendary') }}
    
    UNION ALL 
    
    SELECT 
        trainer,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        notes,
        level,
        move,
        move_number
    FROM {{ ref('stg_trainers_gym_leaders') }}
    
    UNION ALL 
    
    SELECT 
        trainer,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        notes,
        level,
        move,
        ROW_NUMBER() OVER (PARTITION BY pkmn_id ORDER BY move) AS move_number
    FROM mandatory_trainers_with_moves
	QUALIFY ROW_NUMBER() OVER(PARTITION BY pkmn_id ORDER BY move) <= 4

)


SELECT
    T.trainer,
    T.game_stage,
    R.order, 
    T.notes,
    T.pkmn_id,
    S.pokedex,
    T.pokemon,
    T.level,
    MAX(CASE WHEN T.move_number = 1 THEN move END) as move_1,
    MAX(CASE WHEN T.move_number = 2 THEN move END) as move_2,
    MAX(CASE WHEN T.move_number = 3 THEN move END) as move_3,
    MAX(CASE WHEN T.move_number = 4 THEN move END) as move_4
FROM all_trainers as T
INNER JOIN {{ ref('stg_game_route_order') }} as R ON T.nearest_route = R.map
INNER JOIN {{ ref('stg_pkmn_stats') }} as S ON T.pokemon = S.pokemon
WHERE LOWER(T.game_stage) NOT LIKE '%_alt%'
GROUP BY ALL