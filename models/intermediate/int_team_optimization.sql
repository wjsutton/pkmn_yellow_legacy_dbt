WITH battle_prep AS (
    SELECT 
        game_stage,
        trainer,
        is_gym_leader,
        player_pkmn_id,
        trainer_pkmn_id,
        player_pkmn_move,
        CASE WHEN player_pkmn_move_origin = 'single-use-tm' THEN 1 ELSE 0 END as single_use_tm,
        battle_score,
        player_attempts_to_ko,
        trainer_attempts_to_ko,
        player_speed
    FROM {{ ref('int_battle_analysis') }} 
),

-- Find best move for each pokemon matchup
best_move_per_matchup AS (
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['player_pkmn_id','trainer_pkmn_id']) }} as matchup_id,
        game_stage,
        trainer,
        is_gym_leader,
        player_pkmn_id,
        trainer_pkmn_id,
        player_pkmn_move,
        battle_score 
    FROM battle_prep 
    WHERE single_use_tm = 0  -- Exclude single-use TMs from best move analysis
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY player_pkmn_id, trainer_pkmn_id 
        ORDER BY battle_score DESC
    ) = 1
),

-- Calculate battle difficulty metrics for each trainer pokemon
trainer_battle_difficulty AS (
    SELECT
        trainer,
        trainer_pkmn_id,
        AVG(battle_score) as avg_battle_score,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY battle_score DESC) as top_quartile_score,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY battle_score DESC) as bottom_quartile_score,
        COUNT(*) as total_matchups,
        COUNT(CASE WHEN battle_score > 0.8 THEN 1 END) as easy_win_options,
        -- Add difficulty rating
        CASE
            WHEN AVG(battle_score) < 0.3 THEN 'Very Hard'
            WHEN AVG(battle_score) < 0.5 THEN 'Hard'
            WHEN AVG(battle_score) < 0.7 THEN 'Medium'
            WHEN COUNT(CASE WHEN battle_score > 0.8 THEN 1 END) <= 2 THEN 'Requires Specific Counter'
            ELSE 'Easy'
        END as difficulty_rating
    FROM best_move_per_matchup
    GROUP BY trainer, trainer_pkmn_id
),

-- Rank pokemon matchups for team optimization
pokemon_matchup_rankings AS (
    SELECT 
        trainer_pkmn_id,
        player_pkmn_id,
        battle_score,
        RANK() OVER(
            PARTITION BY game_stage, trainer_pkmn_id 
            ORDER BY battle_score DESC, player_attempts_to_ko ASC, player_speed DESC, trainer_attempts_to_ko DESC
        ) as matchup_rank
    FROM battle_prep
),

-- Identify top-tier pokemon (those with good matchups)
top_tier_pokemon AS (
    SELECT 
        player_pkmn_id,
        MIN(matchup_rank) as best_matchup_rank
    FROM pokemon_matchup_rankings
    GROUP BY player_pkmn_id
    HAVING MIN(matchup_rank) <= 5  -- Only pokemon with at least one top-5 matchup
),

-- Final optimization recommendations
team_optimization_prep AS (
    SELECT 
        BP.game_stage,
        BP.trainer,
        BP.is_gym_leader,
        BP.player_pkmn_id,
        BP.trainer_pkmn_id,
        BP.player_pkmn_move,
        BP.single_use_tm,
        BP.battle_score,
        TBD.difficulty_rating as trainer_difficulty,
        TBD.avg_battle_score as trainer_avg_score,
        TBD.easy_win_options as trainer_easy_wins
    FROM battle_prep as BP
    INNER JOIN top_tier_pokemon as TTP ON BP.player_pkmn_id = TTP.player_pkmn_id
    INNER JOIN trainer_battle_difficulty as TBD ON BP.trainer_pkmn_id = TBD.trainer_pkmn_id
)

SELECT 
    {{ dbt_utils.generate_surrogate_key(['player_pkmn_id','trainer_pkmn_id','single_use_tm']) }} as id,
    game_stage,
    trainer,
    is_gym_leader,
    player_pkmn_id,
    trainer_pkmn_id,
    player_pkmn_move,
    single_use_tm,
    battle_score,
    trainer_difficulty,
    trainer_avg_score,
    trainer_easy_wins,
    {{ difficulty_priority() }} as difficulty_priority,
    CASE 
        WHEN single_use_tm = 1 AND battle_score > (trainer_avg_score + {{ tm_efficiency_threshold() }})
        THEN 1 
        ELSE 0 
    END as tm_worth_using,
    CASE 
        WHEN trainer_difficulty IN ('Very Hard', 'Hard', 'Requires Specific Counter') 
        THEN 1 
        ELSE 0 
    END as priority_opponent
FROM team_optimization_prep
QUALIFY ROW_NUMBER() OVER(
    PARTITION BY player_pkmn_id, trainer_pkmn_id, single_use_tm 
    ORDER BY battle_score DESC
) = 1