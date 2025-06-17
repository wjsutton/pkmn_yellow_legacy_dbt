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
    LEFT JOIN {{ ref('stg_moves_from_level_up') }} as M ON T.pokemon = M.pokemon
    WHERE T.level >= M.level
),

all_trainers AS (
    {{ get_trainer_moves('stg_trainers_legendary', 'Legendary') }}
    
    UNION ALL 
    
    {{ get_trainer_moves('stg_trainers_gym_leaders') }}
    
    UNION ALL 
    
    SELECT 
        trainer,
        0 as is_gym_leader,
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
),

trainer_roster AS (
    SELECT
        T.trainer,
        T.is_gym_leader,
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
),

distinct_trainers AS (
    SELECT DISTINCT
        trainer,
        game_stage,
        notes
    FROM trainer_roster
),

trainer_run_combinations AS (
    {{ generate_trainer_run_combinations() }}
)

-- Main output: Complete trainer and pokemon roster with routes
SELECT
    -- Trainer identification
    tr.trainer,
    tr.is_gym_leader,
    tr.game_stage,
    tr.order,
    tr.notes,
    
    -- Pokemon details
    tr.pkmn_id,
    tr.pokedex,
    tr.pokemon,
    tr.level,
    
    -- Movesets
    tr.move_1,
    tr.move_2,
    tr.move_3,
    tr.move_4,
    
    -- Additional route/run information from combinations
    -- trc.run
FROM trainer_roster as tr
-- LEFT JOIN trainer_run_combinations as trc 
--     ON tr.trainer = trc.trainer 
--     AND tr.game_stage = trc.game_stage