{{ config(materialized='table') }}

WITH battle_matchups AS (
    -- Get best battle performance for each pokemon vs each opponent
    SELECT 
        BA.game_stage,
        BA.player_pkmn_id,
        BA.player_pokemon,
        BA.trainer,
        BA.trainer_pkmn_id,
        BA.trainer_pokemon,
        BA.is_gym_leader,
        BA.battle_score,
        BA.player_pkmn_move,
        BA.player_move_single_use_tm,
        -- Get difficulty rating for penalty calculation
        DR.difficulty_rating,
        -- Rank moves by battle score for each matchup
        ROW_NUMBER() OVER(
            PARTITION BY BA.player_pkmn_id, BA.trainer_pkmn_id 
            ORDER BY BA.battle_score DESC
        ) as move_rank
    FROM {{ ref('int_battle_analysis') }} BA
    LEFT JOIN {{ ref('int_trainer_difficulty') }} DR 
        ON BA.trainer = DR.trainer
),

best_matchups AS (
    -- Keep only the best move for each pokemon vs opponent matchup
    SELECT *
    FROM battle_matchups
    WHERE move_rank = 1
),

difficulty_penalties AS (
    -- Apply difficulty-based penalties matching Python logic
    SELECT 
        *,
        -- Difficulty thresholds from Python calculate_route_score function
        {{ calculate_difficulty_penalty('battle_score', 'difficulty_rating') }} as difficulty_threshold,
        -- Calculate penalty if below threshold (matches Python logic)
        {{ calculate_threshold_penalty('battle_score', 'difficulty_rating') }} as threshold_penalty
    FROM best_matchups
),

stage_scores AS (
    -- Calculate overall score per pokemon per stage (matches Python calculate_route_score)
    SELECT 
        game_stage,
        player_pkmn_id,
        player_pokemon,
        -- Base score: sum of all battle scores
        SUM(battle_score) as base_score,
        -- Total penalty: sum of threshold penalties * 2 (heavy penalty multiplier from Python)
        SUM(threshold_penalty * 2.0) as total_penalty,
        -- Final score: base - penalties, minimum 0 (matches Python logic)
        GREATEST(0, SUM(battle_score) - SUM(threshold_penalty * 2.0)) as route_score,
        -- Track TM dependencies
        COUNT(CASE WHEN player_move_single_use_tm = 1 THEN 1 END) as tm_dependent_wins,
        COUNT(*) as total_matchups,
        -- Track gym leader performance for weighting
        COUNT(CASE WHEN is_gym_leader = 1 THEN 1 END) as gym_leader_matchups,
        AVG(CASE WHEN is_gym_leader = 1 THEN battle_score END) as avg_gym_score
    FROM difficulty_penalties
    GROUP BY game_stage, player_pkmn_id, player_pokemon
),

pokemon_stage_performance AS (
    -- Final performance calculation per pokemon per stage
    SELECT 
        game_stage,
        player_pkmn_id,
        player_pokemon,
        route_score,
        base_score,
        total_penalty,
        tm_dependent_wins,
        total_matchups,
        gym_leader_matchups,
        avg_gym_score,
        -- Team selection score combining route performance
        route_score as team_selection_score,
        -- Performance tier based on route score
        {{ calculate_performance_tier('route_score', 'pokemon') }} as performance_tier,
        -- TM efficiency rating
        {{ calculate_tm_efficiency_rating('tm_dependent_wins', 'pokemon') }} as tm_efficiency,
        -- Stage ranking
        ROW_NUMBER() OVER(
            PARTITION BY game_stage 
            ORDER BY route_score DESC, avg_gym_score DESC NULLS LAST
        ) as stage_rank
    FROM stage_scores
)

SELECT 
    game_stage,
    player_pkmn_id,
    player_pokemon,
    team_selection_score,
    route_score,
    base_score,
    total_penalty,
    performance_tier,
    tm_efficiency,
    tm_dependent_wins,
    total_matchups,
    gym_leader_matchups,
    avg_gym_score,
    stage_rank,
    -- Team recommendation
    CASE 
        WHEN stage_rank <= 6 THEN 'Core Team Candidate'
        WHEN stage_rank <= 12 THEN 'Backup Option'
        ELSE 'Situational Use'
    END as team_recommendation
FROM pokemon_stage_performance
ORDER BY game_stage, stage_rank