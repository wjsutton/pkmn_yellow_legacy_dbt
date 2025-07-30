{{ config(materialized='table') }}

WITH team_candidates AS (
    -- Get potential team members (top performers per stage)
    SELECT 
        game_stage,
        player_pkmn_id,
        player_pokemon,
        stage_rank
    FROM {{ ref('opt_pokemon_performance_by_stage') }}
    WHERE stage_rank <= 12  -- Consider top 12 as potential team members
),

tm_battle_data AS (
    -- Get battle data for TM moves only
    SELECT 
        BA.game_stage,
        BA.player_pkmn_id,
        BA.player_pokemon,
        BA.player_pkmn_move as tm_move,
        BA.battle_score,
        -- Rank moves by battle score for each pokemon vs opponent
        ROW_NUMBER() OVER(
            PARTITION BY BA.player_pkmn_id, BA.trainer_pkmn_id 
            ORDER BY BA.battle_score DESC
        ) as move_rank
    FROM {{ ref('int_battle_analysis') }} BA
    INNER JOIN team_candidates TC ON BA.player_pkmn_id = TC.player_pkmn_id 
        AND BA.game_stage = TC.game_stage
    WHERE BA.player_move_single_use_tm = 1
),

pokemon_tm_scores AS (
    -- Calculate average battle score per pokemon per TM move
    SELECT 
        game_stage,
        player_pkmn_id,
        player_pokemon,
        tm_move,
        AVG(battle_score) as avg_battle_score,
        COUNT(*) as matchup_count
    FROM tm_battle_data
    WHERE move_rank = 1  -- Only consider best move scenarios
    GROUP BY game_stage, player_pkmn_id, player_pokemon, tm_move
),

tm_rankings AS (
    -- Rank pokemon by their effectiveness with each TM
    SELECT 
        game_stage,
        tm_move,
        player_pkmn_id,
        player_pokemon,
        avg_battle_score,
        ROW_NUMBER() OVER(
            PARTITION BY game_stage, tm_move 
            ORDER BY avg_battle_score DESC
        ) as tm_rank
    FROM pokemon_tm_scores
),

tm_assignments AS (
    -- Assign each TM to its best user (greedy algorithm)
    SELECT 
        game_stage,
        tm_move,
        player_pkmn_id as assigned_to_pkmn_id,
        player_pokemon as assigned_to_pokemon,
        avg_battle_score as assignment_score,
        -- Check if there are conflicts (multiple users)
        COUNT(*) OVER(PARTITION BY game_stage, tm_move) as total_users,
        CASE 
            WHEN COUNT(*) OVER(PARTITION BY game_stage, tm_move) > 1 THEN 1 
            ELSE 0 
        END as has_conflict
    FROM tm_rankings
    WHERE tm_rank = 1  -- Only the best user gets the TM
),

pokemon_tm_loadouts AS (
    -- Determine final TM loadout per pokemon
    SELECT 
        PTS.game_stage,
        PTS.player_pkmn_id,
        PTS.player_pokemon,
        -- Count allocated TMs
        COUNT(TA.tm_move) as tms_allocated,
        -- Count denied TMs (wanted but didn't get)
        COUNT(PTS.tm_move) - COUNT(TA.tm_move) as tms_denied,
        -- Get primary assigned TM (highest scoring)
        MAX(CASE WHEN TA.tm_move IS NOT NULL THEN TA.tm_move END) as assigned_tm_move,
        -- List all allocated TMs
        LISTAGG(TA.tm_move, ', ') as allocated_tm_list
    FROM pokemon_tm_scores PTS
    LEFT JOIN tm_assignments TA ON PTS.game_stage = TA.game_stage 
        AND PTS.player_pkmn_id = TA.assigned_to_pkmn_id 
        AND PTS.tm_move = TA.tm_move
    GROUP BY PTS.game_stage, PTS.player_pkmn_id, PTS.player_pokemon
)

SELECT 
    game_stage,
    player_pkmn_id,
    player_pokemon,
    COALESCE(assigned_tm_move, 'None') as assigned_tm_move,
    tms_allocated,
    tms_denied,
    COALESCE(allocated_tm_list, 'None') as allocated_tm_list,
    -- TM efficiency rating
    {{ calculate_tm_efficiency_rating('tms_allocated', 'allocation') }} as tm_efficiency_rating,
    -- Usage recommendation
    {{ calculate_tm_usage_recommendation('tms_allocated') }} as tm_usage_recommendation
FROM pokemon_tm_loadouts
ORDER BY game_stage, player_pkmn_id