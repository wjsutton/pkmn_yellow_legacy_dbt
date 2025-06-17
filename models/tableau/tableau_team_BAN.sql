
WITH CTE AS (

    -- SELECT * FROM {{ ref('teams_optimisation') }} 

    -- UNION ALL

    -- SELECT * FROM {{ ref('teams_optimisation_with_pikachu') }} 

    SELECT * FROM {{ ref('find_best_teams') }}

)
,
moves_pre_pivot AS (
  SELECT 
    run, 
    game_stage,
    player_pkmn_id,
    player_pkmn_move
  FROM CTE
  GROUP BY ALL
),
numbered_moves AS (
  SELECT
    run,
    game_stage,
    player_pkmn_id,
    player_pkmn_move,
    ROW_NUMBER() OVER (
      PARTITION BY run, game_stage, player_pkmn_id
      ORDER BY player_pkmn_move
    ) AS move_num
  FROM moves_pre_pivot
)
SELECT
  run,
  game_stage,
  player_pkmn_id,
  MAX(CASE WHEN move_num = 1 THEN player_pkmn_move END) AS move_1,
  MAX(CASE WHEN move_num = 2 THEN player_pkmn_move END) AS move_2,
  MAX(CASE WHEN move_num = 3 THEN player_pkmn_move END) AS move_3,
  MAX(CASE WHEN move_num = 4 THEN player_pkmn_move END) AS move_4
FROM numbered_moves
GROUP BY ALL
ORDER BY run, game_stage, player_pkmn_id

