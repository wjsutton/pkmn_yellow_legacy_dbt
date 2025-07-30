{{ config(materialized='table') }}

WITH team_compositions AS (
    -- Get the optimal team compositions from stage selection
    SELECT 
        run_name,
        game_stage, 
        keep_pikachu,
        no_legends,
        player_pkmn_id,
        player_pokemon,
        team_rank,
        pokemon_score,
        performance_tier,
        assigned_tm_move,
        tms_allocated,
        team_performance_score,
        team_quality,
        variant_description
    FROM {{ ref('opt_recommended_teams') }}
),

battle_matchups AS (
    -- Get detailed battle analysis for the selected teams
    SELECT 
        TC.run_name,
        TC.game_stage,
        TC.player_pkmn_id,
        TC.player_pokemon,
        TC.assigned_tm_move,
        BA.trainer,
        BA.trainer_pkmn_id,
        BA.trainer_pokemon,
        BA.is_gym_leader,
        BA.battle_score,
        BA.player_pkmn_move,
        BA.player_move_single_use_tm,
        -- Flag if this is the assigned move for this pokemon
        CASE 
            WHEN BA.player_pkmn_move = TC.assigned_tm_move THEN 1
            ELSE 0
        END as is_assigned_move,
        -- Rank moves by battle score for best matchup identification
        ROW_NUMBER() OVER(
            PARTITION BY TC.player_pkmn_id, BA.trainer_pkmn_id 
            ORDER BY BA.battle_score DESC
        ) as move_rank
    FROM team_compositions TC
    INNER JOIN {{ ref('int_battle_analysis') }} BA 
        ON TC.game_stage = BA.game_stage 
        AND TC.player_pkmn_id = BA.player_pkmn_id
),

best_matchups AS (
    -- Keep only the best move for each matchup (matches Python matchup_analysis)
    SELECT *
    FROM battle_matchups
    WHERE move_rank = 1
),

team_summary AS (
    -- Summarize team performance (matches Python team scoring)
    SELECT 
        run_name,
        game_stage,
        COUNT(DISTINCT player_pkmn_id) as team_size,
        AVG(pokemon_score) as avg_pokemon_score,
        SUM(tms_allocated) as total_tms,
        STRING_AGG(DISTINCT player_pokemon, ', ' ORDER BY player_pokemon) as team_members,
        FIRST_VALUE(team_performance_score) OVER(PARTITION BY run_name, game_stage) as best_score,
        FIRST_VALUE(variant_description) OVER(PARTITION BY run_name, game_stage) as variant_type
    FROM team_compositions
    GROUP BY run_name, game_stage, team_performance_score, variant_description
),

tm_conflict_analysis AS (
    -- Analyze TM conflicts and resolutions (matches Python TM conflict reporting)
    SELECT 
        TC.run_name,
        TC.game_stage,
        TC.assigned_tm_move as tm_move,
        COUNT(DISTINCT TC.player_pkmn_id) as potential_users,
        STRING_AGG(TC.player_pokemon, ', ' ORDER BY TC.pokemon_score DESC) as pokemon_list,
        FIRST_VALUE(TC.player_pokemon) OVER(
            PARTITION BY TC.run_name, TC.game_stage, TC.assigned_tm_move 
            ORDER BY TC.pokemon_score DESC
        ) as assigned_to_pokemon,
        CASE 
            WHEN COUNT(DISTINCT TC.player_pkmn_id) > 1 THEN 'Conflict Resolved'
            ELSE 'No Conflict'
        END as conflict_status
    FROM team_compositions TC
    WHERE TC.assigned_tm_move != 'None'
    GROUP BY TC.run_name, TC.game_stage, TC.assigned_tm_move
),

formatted_output AS (
    -- Format output to match Python script structure
    SELECT 
        TC.run_name as run,
        TC.game_stage,
        TC.player_pkmn_id,
        TC.player_pokemon,
        BM.trainer,
        BM.trainer_pkmn_id,
        BM.trainer_pokemon,
        BM.is_gym_leader,
        BM.battle_score,
        BM.player_pkmn_move,
        BM.player_move_single_use_tm as single_use_tm,
        BM.is_assigned_move,
        -- Team metadata (matches Python best_df structure)
        TS.best_score,
        TS.team_size,
        TS.total_tms,
        TS.variant_type,
        -- Pokemon metadata
        TC.team_rank,
        TC.pokemon_score,
        TC.performance_tier,
        TC.assigned_tm_move,
        TC.tms_allocated,
        -- Battle context
        CASE WHEN BM.is_gym_leader = 1 THEN 'Gym Leader' ELSE 'Trainer' END as trainer_type,
        -- Priority ranking for key matchups
        CASE 
            WHEN BM.is_gym_leader = 1 THEN 1
            WHEN BM.battle_score < 0.4 THEN 2  -- Difficult matchups
            ELSE 3
        END as matchup_priority
    FROM team_compositions TC
    INNER JOIN best_matchups BM ON TC.run_name = BM.run_name 
        AND TC.game_stage = BM.game_stage 
        AND TC.player_pkmn_id = BM.player_pkmn_id
    INNER JOIN team_summary TS ON TC.run_name = TS.run_name 
        AND TC.game_stage = TS.game_stage
)

SELECT 
    run,
    game_stage,
    player_pkmn_id,
    player_pokemon,
    trainer,
    trainer_pkmn_id, 
    trainer_pokemon,
    trainer_type,
    is_gym_leader,
    battle_score,
    player_pkmn_move,
    single_use_tm,
    is_assigned_move,
    -- Team information
    best_score,
    team_size,
    total_tms,
    variant_type,
    -- Pokemon information  
    team_rank,
    pokemon_score,
    performance_tier,
    assigned_tm_move,
    tms_allocated,
    matchup_priority,
    -- Additional context for analysis
    {{ calculate_move_category('is_assigned_move', 'single_use_tm') }} as move_category,
    -- Battle difficulty assessment
    {{ calculate_battle_difficulty('battle_score') }} as matchup_difficulty
FROM formatted_output
ORDER BY 
    run, 
    game_stage, 
    team_rank, 
    matchup_priority,
    trainer,
    battle_score DESC