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
        -- Get difficulty weighting for team contribution calculation
        DR.difficulty_score,
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

best_team_options AS (
    -- For each trainer battle, identify which pokemon has the best battle_score
    SELECT 
        BM.*,
        -- Rank pokemon by battle score for each trainer battle
        ROW_NUMBER() OVER(
            PARTITION BY BM.game_stage, BM.trainer_pkmn_id 
            ORDER BY BM.battle_score DESC
        ) as team_rank
    FROM best_matchups BM
),

team_contributions AS (
    -- Calculate weighted contributions where each pokemon gets credit for battles they're best at
    SELECT 
        BTO.game_stage,
        BTO.player_pkmn_id,
        BTO.player_pokemon,
        BTO.trainer,
        BTO.trainer_pkmn_id,
        BTO.trainer_pokemon,
        BTO.battle_score,
        BTO.difficulty_score,
        BTO.difficulty_rating,
        BTO.is_gym_leader,
        BTO.player_pkmn_move,
        BTO.player_move_single_use_tm,
        BTO.team_rank,
        -- Calculate battle weight based on difficulty
        CASE 
            WHEN BTO.is_gym_leader = 1 THEN BTO.difficulty_score * 3.0  -- Gym leaders 3x weight
            WHEN BTO.difficulty_rating IN ('Very Hard', 'Extreme') THEN BTO.difficulty_score * 2.0  -- Hard battles 2x weight
            ELSE BTO.difficulty_score  -- Standard weight
        END as battle_weight,
        -- Contribution: battle_score * weight (only for best team option)
        CASE 
            WHEN BTO.team_rank = 1 THEN BTO.battle_score * 
                CASE 
                    WHEN BTO.is_gym_leader = 1 THEN BTO.difficulty_score * 3.0
                    WHEN BTO.difficulty_rating IN ('Very Hard', 'Extreme') THEN BTO.difficulty_score * 2.0
                    ELSE BTO.difficulty_score
                END
            ELSE 0  -- No contribution if not the best option for this battle
        END as weighted_contribution
    FROM best_team_options BTO
),

stage_scores AS (
    -- Calculate team contribution score per pokemon per stage
    SELECT 
        game_stage,
        player_pkmn_id,
        player_pokemon,
        -- Team contribution score: sum of weighted contributions where this pokemon is best
        SUM(weighted_contribution) as team_contribution_score,
        -- Keep some legacy metrics for analysis
        SUM(battle_score) as base_score,
        0 as total_penalty,  -- No penalties in new system
        SUM(weighted_contribution) as route_score,  -- Route score = team contribution
        -- Track TM dependencies for battles where this pokemon is the best option
        COUNT(CASE WHEN team_rank = 1 AND player_move_single_use_tm = 1 THEN 1 END) as tm_dependent_wins,
        COUNT(CASE WHEN team_rank = 1 THEN 1 END) as battles_as_best_option,
        COUNT(*) as total_matchups,
        -- Track gym leader performance for weighting
        COUNT(CASE WHEN is_gym_leader = 1 AND team_rank = 1 THEN 1 END) as gym_leader_best_matchups,
        AVG(CASE WHEN is_gym_leader = 1 AND team_rank = 1 THEN battle_score END) as avg_gym_score
    FROM team_contributions
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
        battles_as_best_option,
        total_matchups,
        gym_leader_best_matchups,
        avg_gym_score,
        -- Team selection score is now the team contribution score
        team_contribution_score as team_selection_score,
        -- Performance tier based on team contribution score
        {{ calculate_performance_tier('team_contribution_score', 'pokemon') }} as performance_tier,
        -- TM efficiency rating based on battles where this pokemon is the best option
        {{ calculate_tm_efficiency_rating('tm_dependent_wins', 'pokemon') }} as tm_efficiency,
        -- Stage ranking based on team contribution
        ROW_NUMBER() OVER(
            PARTITION BY game_stage 
            ORDER BY team_contribution_score DESC, avg_gym_score DESC NULLS LAST
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
    battles_as_best_option,
    total_matchups,
    gym_leader_best_matchups,
    avg_gym_score,
    stage_rank,
    -- Team recommendation based on contribution ranking
    CASE 
        WHEN stage_rank <= 6 THEN 'Core Team Candidate'
        WHEN stage_rank <= 12 THEN 'Backup Option'
        ELSE 'Situational Use'
    END as team_recommendation
FROM pokemon_stage_performance
ORDER BY game_stage, stage_rank