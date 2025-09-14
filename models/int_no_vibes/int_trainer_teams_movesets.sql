WITH trainers_with_defined_moves AS (
    SELECT 
        trainer,
        'Legendary' as type,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        pkmn_level,
        move,
        move_number
    FROM {{ ref('stg_trainers_legendary') }}
    
    UNION ALL
    
    SELECT 
        trainer,
        'Gym Leader' as type,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        pkmn_level,
        move,
        move_number
    FROM {{ ref('stg_trainers_gym_leaders') }}
),

trainers_without_defined_moves AS (

    SELECT 
        T.trainer,
        'Mandatory' as type,
        T.pkmn_id,
        T.nearest_route,
        T.pokemon,
        T.game_stage,
        T.pkmn_level,
        M.move,
        ROW_NUMBER() OVER (PARTITION BY T.pkmn_id ORDER BY M.move) AS move_number
    FROM {{ ref('stg_trainers_mandatory') }} as T
    INNER JOIN {{ ref('int_pkmn_movesets') }} as M 
        ON T.pokemon = M.pokemon
    WHERE M.move_origin = 'level-up'
        AND T.pkmn_level >= M.pkmn_level
    QUALIFY ROW_NUMBER() OVER(PARTITION BY T.pkmn_id ORDER BY M.move) <= 4
),

all_trainers AS (

    SELECT * FROM trainers_with_defined_moves
    UNION ALL
    SELECT * FROM trainers_without_defined_moves
),

trainer_roster AS (
    SELECT
        T.trainer,
        T.type,
        T.game_stage,
        R.game_order, 
        T.pkmn_id,
        S.pokedex,
        T.pokemon,
        T.pkmn_level,
        T.move
    FROM all_trainers as T
    INNER JOIN {{ ref('stg_game_route_order') }} as R ON T.nearest_route = R.map
    INNER JOIN {{ ref('stg_pkmn_stats') }} as S ON T.pokemon = S.pokemon
    WHERE LOWER(T.game_stage) NOT LIKE '%_alt%'
    GROUP BY ALL
)

SELECT
    -- Trainer identification
    tr.trainer,
    tr.type,
    tr.game_stage,
    tr.game_order,

    -- CASE
    --     WHEN tr.trainer LIKE 'Rival_1' THEN NULL
    --     WHEN tr.trainer LIKE 'Rival_2' THEN NULL
    --     WHEN tr.trainer LIKE 'Rival_3' THEN NULL
    --     WHEN tr.trainer LIKE 'Rival_4' THEN NULL
    --     WHEN tr.trainer LIKE 'Rival_%_%' 
    --     THEN REGEXP_SUBSTR(tr.trainer, '[^_]+$', 1, 1)
    --     WHEN tr.trainer LIKE 'Champion_%' 
    --     THEN REGEXP_SUBSTR(tr.trainer, '[^_]+$', 1, 1)
    --     ELSE NULL
    -- END as rival_variant,
    
    -- Pokemon details
    tr.pkmn_id,
    tr.pokedex,
    tr.pokemon,
    tr.pkmn_level,
    
    tr.move,
    S.type as move_type,
    S.power as move_power,
    S.acc as move_accuracy,
    S.pp as move_pp,
    S.hits as move_hits,
    S.hits_min as move_hits_min,
    S.hits_max as move_hits_max,
    S.critical_hit_ratio,
    PS.stat_used as move_stat_used
FROM trainer_roster as tr
INNER JOIN {{ ref('stg_moves_stats') }} S ON tr.move = S.move
INNER JOIN {{ ref('stg_moves_phys_spec') }} PS ON PS.type = S.type
WHERE move_power <> 'N/A'  
ORDER BY game_order