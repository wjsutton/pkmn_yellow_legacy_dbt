
WITH best_move as (
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['player_pkmn_id','trainer_pkmn_id']) }} as id,
        game_stage,
        trainer,
        is_gym_leader,
        player_pkmn_id,
        trainer_pkmn_id,
        player_pkmn_move,
        battle_score 
    FROM {{ ref('int_pkmn_move_damage') }} 
    WHERE player_pkmn_move_origin <> 'single-use-tm'
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id ORDER BY battle_score DESC) = 1
)

, battle_scores AS (
  SELECT
    trainer,
    trainer_pkmn_id,
    AVG(battle_score) as avg_battle_score,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY battle_score DESC) as top_quartile_score,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY battle_score DESC) as bottom_quartile_score,
    COUNT(*) as total_matchups,
    COUNT(CASE WHEN battle_score > 0.8 THEN 1 END) as easy_win_options
  FROM best_move
  GROUP BY trainer, trainer_pkmn_id
)

, battle_difficulty AS (
  SELECT
    *,
    CASE
      WHEN avg_battle_score < 0.3 THEN 'Very Hard'
      WHEN avg_battle_score < 0.5 THEN 'Hard'
      WHEN avg_battle_score < 0.7 THEN 'Medium'
      WHEN easy_win_options <= 2 THEN 'Requires Specific Counter'
      ELSE 'Easy'
    END as difficulty_rating
  FROM battle_scores
)

SELECT * FROM battle_difficulty