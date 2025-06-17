WITH trainer_max_levels AS (
    -- Gym Leaders
    SELECT 
        G.trainer,
        G.game_stage,
        MAX(R.order) AS order,
        MAX(G.level) AS max_level,
        'Gym Leader' as trainer_type
    FROM {{ ref('stg_trainers_gym_leaders') }} AS G
    INNER JOIN {{ ref('stg_game_route_order') }} AS R 
        ON G.nearest_route = R.map
    GROUP BY G.trainer, G.game_stage

    UNION ALL 

    -- Legendary trainers (Smith)
    SELECT 
        G.trainer,
        G.game_stage,
        MAX(R.order) AS order,
        MAX(G.level) AS max_level,
        'Legendary' as trainer_type
    FROM {{ ref('stg_trainers_legendary') }} AS G
    INNER JOIN {{ ref('stg_game_route_order') }} AS R 
        ON G.nearest_route = R.map
    WHERE G.trainer = 'Smith'
    GROUP BY G.trainer, G.game_stage
),

level_caps AS (
    SELECT DISTINCT
        G.game_stage,
        -- Special case for Badge_3
        MAX(CASE 
            WHEN G.game_stage = 'Badge_3' THEN 24 
            ELSE G.max_level 
        END) AS level_cap
    FROM trainer_max_levels AS G
    INNER JOIN {{ ref('stg_game_route_order') }} AS R 
        ON R.order <= G.order
    GROUP BY G.game_stage
),

route_mapping AS (
    SELECT 
        next_gym,
        MAX("order") AS last_order
    FROM {{ ref('stg_game_route_order') }}
    GROUP BY next_gym
),

final_caps AS (
    SELECT 
        lc.game_stage,
        lc.level_cap,
        rm.last_order
    FROM level_caps lc
    LEFT JOIN route_mapping rm 
        ON rm.next_gym = LEFT(lc.game_stage, 7)
)

SELECT 
    game_stage,
    level_cap,
    COALESCE(
        last_order,
        MAX(last_order) OVER (
            ORDER BY level_cap 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
    ) AS stage_order
FROM final_caps