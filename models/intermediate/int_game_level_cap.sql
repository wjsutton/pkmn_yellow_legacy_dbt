
WITH gym_leaders AS (
    SELECT 
        G.trainer,
        G.game_stage,
        MAX(R.order) AS order,
        MAX(G.level) AS max_level
    FROM {{ ref('stg_trainers_gym_leaders') }} AS G
    INNER JOIN {{ ref('stg_game_route_order') }} AS R 
      ON G.nearest_route = R.map
    GROUP BY ALL
),

smith AS (
    SELECT 
        G.trainer,
        G.game_stage,
        MAX(R.order) AS order,
        MAX(G.level) AS max_level
    FROM {{ ref('stg_trainers_legendary') }} AS G
    INNER JOIN {{ ref('stg_game_route_order') }} AS R 
      ON G.nearest_route = R.map
    WHERE G.trainer = 'Smith'
    GROUP BY ALL
),

gym_leaders_and_smith AS (

    SELECT * FROM gym_leaders
        UNION ALL 
    SELECT * FROM smith

),

base AS (
    SELECT DISTINCT
        G.game_stage,
        MAX(CASE WHEN G.game_stage = 'Badge_3' THEN 24 ELSE G.max_level END) AS level_cap
    FROM gym_leaders_and_smith AS G
    INNER JOIN {{ ref('stg_game_route_order') }} AS R 
      ON R.order <= G.order
    WHERE R.order <= G.order
    GROUP BY G.game_stage
),

last_order AS (
    SELECT 
        next_gym,
        MAX("order") AS last_order
    FROM {{ ref('stg_game_route_order') }}
    GROUP BY next_gym
),

joined AS (
    SELECT 
        base.game_stage,
        base.level_cap,
        last_order.last_order
    FROM base
    LEFT JOIN last_order 
      ON last_order.next_gym = LEFT(base.game_stage, 7)
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
    ) AS filled_last_order
FROM joined
