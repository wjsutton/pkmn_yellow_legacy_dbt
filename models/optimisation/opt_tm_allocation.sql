WITH tm_move_requirements AS (
    -- Identify all single-use TM moves needed for optimal performance
    SELECT 
        BA.game_stage,
        BA.player_pkmn_id,
        BA.player_pokemon,
        BA.player_pkmn_move as tm_move,
        BA.trainer,
        BA.trainer_pokemon,
        BA.battle_score,
        BA.is_gym_leader,
        -- Priority scoring for TM allocation
        CASE 
            WHEN BA.is_gym_leader = 1 THEN BA.battle_score * 3  -- Gym leaders highest priority
            WHEN BA.battle_score >= 0.8 THEN BA.battle_score * 2  -- Excellent matchups
            ELSE BA.battle_score
        END as tm_priority_score,
        ROW_NUMBER() OVER(
            PARTITION BY BA.player_pkmn_id, BA.trainer_pkmn_id 
            ORDER BY BA.battle_score DESC
        ) as move_preference_rank
    FROM {{ ref('int_battle_analysis') }} BA
    WHERE BA.player_move_single_use_tm = 1
        AND BA.battle_score >= 0.4  -- Only consider TMs that provide decent advantage
),

tm_usage_analysis AS (
    -- Analyze how each TM move is used across different pokemon
    SELECT 
        tm_move,
        COUNT(DISTINCT player_pkmn_id) as pokemon_users,
        COUNT(DISTINCT game_stage) as stages_used,
        AVG(tm_priority_score) as avg_priority,
        MAX(tm_priority_score) as max_priority,
        SUM(tm_priority_score) as total_priority,
        -- Identify the best user for each TM
        FIRST_VALUE(player_pkmn_id) OVER(
            PARTITION BY tm_move 
            ORDER BY tm_priority_score DESC, battle_score DESC
        ) as best_user_pkmn_id,
        FIRST_VALUE(player_pokemon) OVER(
            PARTITION BY tm_move 
            ORDER BY tm_priority_score DESC, battle_score DESC
        ) as best_user_pokemon,
        FIRST_VALUE(tm_priority_score) OVER(
            PARTITION BY tm_move 
            ORDER BY tm_priority_score DESC, battle_score DESC
        ) as best_user_priority
    FROM tm_move_requirements
    WHERE move_preference_rank = 1  -- Only consider cases where TM is the best move
    GROUP BY tm_move, player_pkmn_id, player_pokemon, tm_priority_score, battle_score
),

tm_conflicts AS (
    -- Identify TM conflicts where multiple pokemon want the same TM
    SELECT 
        tm_move,
        pokemon_users,
        stages_used,
        avg_priority,
        max_priority,
        total_priority,
        best_user_pkmn_id,
        best_user_pokemon,
        best_user_priority,
        CASE 
            WHEN pokemon_users > 1 THEN 'Conflict'
            ELSE 'No Conflict'
        END as conflict_status,
        -- Efficiency rating for TM usage
        CASE 
            WHEN max_priority >= 2.0 THEN 'High Value'
            WHEN max_priority >= 1.5 THEN 'Good Value'  
            WHEN max_priority >= 1.0 THEN 'Moderate Value'
            ELSE 'Low Value'
        END as tm_value_rating
    FROM (
        SELECT 
            tm_move,
            COUNT(DISTINCT player_pkmn_id) as pokemon_users,
            COUNT(DISTINCT game_stage) as stages_used,
            AVG(avg_priority) as avg_priority,
            MAX(max_priority) as max_priority,
            SUM(total_priority) as total_priority,
            FIRST_VALUE(best_user_pkmn_id) OVER(PARTITION BY tm_move ORDER BY best_user_priority DESC) as best_user_pkmn_id,
            FIRST_VALUE(best_user_pokemon) OVER(PARTITION BY tm_move ORDER BY best_user_priority DESC) as best_user_pokemon,
            MAX(best_user_priority) as best_user_priority
        FROM tm_usage_analysis
        GROUP BY tm_move
    ) t
),

greedy_tm_allocation AS (
    -- Implement greedy allocation algorithm: assign each TM to its best user
    SELECT 
        TMR.game_stage,
        TMR.tm_move,
        TMR.player_pkmn_id,
        TMR.player_pokemon,
        TMR.trainer,
        TMR.trainer_pokemon,
        TMR.battle_score,
        TMR.tm_priority_score,
        TC.conflict_status,
        TC.tm_value_rating,
        TC.best_user_pkmn_id,
        TC.best_user_pokemon,
        -- Allocation decision
        CASE 
            WHEN TMR.player_pkmn_id = TC.best_user_pkmn_id THEN 'Allocated'
            WHEN TC.conflict_status = 'Conflict' THEN 'Denied - TM Conflict'
            ELSE 'Available'
        END as allocation_status,
        -- Alternative recommendations for denied allocations
        CASE 
            WHEN TMR.player_pkmn_id != TC.best_user_pkmn_id AND TC.conflict_status = 'Conflict' 
            THEN 'Consider repurchasable TM or level-up alternative'
            ELSE NULL
        END as alternative_suggestion
    FROM tm_move_requirements TMR
    INNER JOIN tm_conflicts TC ON TMR.tm_move = TC.tm_move
    WHERE TMR.move_preference_rank = 1
),

tm_allocation_summary AS (
    -- Summarize TM allocation results
    SELECT 
        tm_move,
        conflict_status,
        tm_value_rating,
        best_user_pokemon as allocated_to_pokemon,
        best_user_pkmn_id as allocated_to_pkmn_id,
        COUNT(CASE WHEN allocation_status = 'Denied - TM Conflict' THEN 1 END) as denied_requests,
        AVG(CASE WHEN allocation_status = 'Allocated' THEN tm_priority_score END) as allocated_priority,
        STRING_AGG(
            CASE WHEN allocation_status = 'Denied - TM Conflict' 
            THEN player_pokemon END, ', '
        ) as denied_pokemon_list
    FROM greedy_tm_allocation
    GROUP BY tm_move, conflict_status, tm_value_rating, best_user_pokemon, best_user_pkmn_id
),

pokemon_tm_summary AS (
    -- Summarize TM allocations per pokemon
    SELECT 
        player_pkmn_id,
        player_pokemon,
        COUNT(CASE WHEN allocation_status = 'Allocated' THEN 1 END) as tms_allocated,
        COUNT(CASE WHEN allocation_status = 'Denied - TM Conflict' THEN 1 END) as tms_denied,
        STRING_AGG(
            CASE WHEN allocation_status = 'Allocated' THEN tm_move END, ', '
        ) as allocated_tm_list,
        STRING_AGG(
            CASE WHEN allocation_status = 'Denied - TM Conflict' THEN tm_move END, ', '
        ) as denied_tm_list,
        AVG(CASE WHEN allocation_status = 'Allocated' THEN tm_priority_score END) as avg_allocated_priority
    FROM greedy_tm_allocation
    GROUP BY player_pkmn_id, player_pokemon
)

-- Final output: TM allocation recommendations
SELECT 
    GTA.game_stage,
    GTA.tm_move,
    GTA.player_pkmn_id,
    GTA.player_pokemon,
    GTA.allocation_status,
    GTA.tm_value_rating,
    GTA.tm_priority_score,
    GTA.battle_score,
    GTA.trainer as benefits_against_trainer,
    GTA.trainer_pokemon as benefits_against_pokemon,
    GTA.alternative_suggestion,
    PTS.tms_allocated as total_tms_for_pokemon,
    PTS.allocated_tm_list as pokemon_tm_loadout,
    -- Usage recommendations
    CASE 
        WHEN GTA.allocation_status = 'Allocated' AND GTA.tm_value_rating = 'High Value' 
        THEN 'Essential TM - high impact on battle performance'
        WHEN GTA.allocation_status = 'Allocated' AND GTA.tm_value_rating = 'Good Value'
        THEN 'Recommended TM - solid performance boost'
        WHEN GTA.allocation_status = 'Allocated' AND GTA.tm_value_rating = 'Moderate Value'
        THEN 'Optional TM - moderate improvement'
        WHEN GTA.allocation_status = 'Denied - TM Conflict'
        THEN 'TM allocated to higher priority pokemon - seek alternatives'
        ELSE 'TM available but low priority'
    END as usage_recommendation,
    -- Efficiency score
    ROUND(GTA.tm_priority_score, 3) as efficiency_score
FROM greedy_tm_allocation GTA
LEFT JOIN pokemon_tm_summary PTS ON GTA.player_pkmn_id = PTS.player_pkmn_id
ORDER BY GTA.game_stage, GTA.tm_priority_score DESC, GTA.allocation_status