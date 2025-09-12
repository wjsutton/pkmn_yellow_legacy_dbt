WITH all_trainer_data AS (
    -- Combine all trainer types
    SELECT 
        trainer,
        0 as is_gym_leader,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        notes,
        pkmn_level
    FROM {{ ref('stg_trainers_mandatory') }}
    
    UNION ALL
    
    SELECT 
        trainer,
        0 as is_gym_leader,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        'Legendary' as notes,
        pkmn_level
    FROM {{ ref('stg_trainers_legendary') }}
    
    UNION ALL
    
    SELECT 
        trainer,
        1 as is_gym_leader,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        notes,
        pkmn_level
    FROM {{ ref('stg_trainers_gym_leaders') }}
),

gym_leader_moves AS (
    -- Use explicit moves from gym leader seed file
    SELECT 
        T.trainer,
        T.is_gym_leader,
        T.pkmn_id,
        T.nearest_route,
        T.pokemon,
        T.game_stage,
        T.notes,
        T.pkmn_level,
        GL.move,
        GL.move_number
    FROM all_trainer_data T
    INNER JOIN {{ ref('stg_trainers_gym_leaders') }} GL 
        ON T.pkmn_id = GL.pkmn_id
    WHERE T.is_gym_leader = 1
),

regular_trainer_moves AS (
    -- Use level-up moves for non-gym leaders
    SELECT 
        T.trainer,
        T.is_gym_leader,
        T.pkmn_id,
        T.nearest_route,
        T.pokemon,
        T.game_stage,
        T.notes,
        T.pkmn_level,
        M.move,
        ROW_NUMBER() OVER (PARTITION BY T.pkmn_id ORDER BY M.move) AS move_number
    FROM all_trainer_data T
    INNER JOIN {{ ref('int_move_sources_unified') }} M 
        ON T.pokemon = M.pokemon
    WHERE T.is_gym_leader = 0
        AND M.move_origin = 'level-up'
        AND T.pkmn_level >= M.pkmn_level
    QUALIFY ROW_NUMBER() OVER(PARTITION BY T.pkmn_id ORDER BY M.move) <= 4
),

all_trainers AS (
    -- Combine gym leaders (explicit moves) with regular trainers (level-up moves)
    SELECT * FROM gym_leader_moves
    UNION ALL
    SELECT * FROM regular_trainer_moves
),

trainer_roster AS (
    SELECT
        T.trainer,
        T.is_gym_leader,
        T.game_stage,
        R.game_order, 
        T.notes,
        T.pkmn_id,
        S.pokedex,
        T.pokemon,
        T.pkmn_level,
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
    tr.game_order,
    tr.notes,
    
    -- Pokemon details
    tr.pkmn_id,
    tr.pokedex,
    tr.pokemon,
    tr.pkmn_level,
    
    -- Movesets
    tr.move_1,
    tr.move_2,
    tr.move_3,
    tr.move_4,
    
    -- Additional route/run information from combinations
    -- trc.run
FROM trainer_roster as tr
ORDER BY game_order
-- Optional: could add run combinations logic here if needed
-- LEFT JOIN trainer_run_combinations as trc 
--     ON tr.trainer = trc.trainer 
--     AND tr.game_stage = trc.game_stage