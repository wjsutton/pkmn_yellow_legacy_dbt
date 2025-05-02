WITH CTE as (
    SELECT 
        game_stage,
        trainer,
        is_gym_leader,
        player_pkmn_id,
        trainer_pkmn_id,
        player_pkmn_move,
        CASE WHEN player_pkmn_move_origin = 'single-use-tm' THEN 1 ELSE 0 END as single_use_tm,
        battle_score 
    FROM {{ ref('int_pkmn_move_damage') }} 
)
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['player_pkmn_id','trainer_pkmn_id','single_use_tm']) }} as id,
        *
    FROM CTE
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id ORDER BY battle_score DESC) = 1
