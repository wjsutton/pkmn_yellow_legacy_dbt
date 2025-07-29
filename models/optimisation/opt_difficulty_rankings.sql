WITH trainer_battle_difficulty AS (
    -- Calculate comprehensive difficulty metrics for each trainer
    SELECT
        BA.game_stage,
        BA.trainer,
        BA.is_gym_leader,
        COUNT(DISTINCT BA.trainer_pkmn_id) as total_pokemon,
        COUNT(DISTINCT BA.player_pkmn_id) as available_counters,
        AVG(BA.battle_score) as avg_battle_score,
        MIN(BA.battle_score) as min_battle_score,
        MAX(BA.battle_score) as max_battle_score,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY BA.battle_score) as bottom_quartile_score,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY BA.battle_score) as top_quartile_score,
        -- Count effective counters by tier
        COUNT(CASE WHEN BA.battle_score >= 0.8 THEN 1 END) as excellent_counters,
        COUNT(CASE WHEN BA.battle_score >= 0.6 THEN 1 END) as good_counters,
        COUNT(CASE WHEN BA.battle_score >= 0.4 THEN 1 END) as decent_counters,
        COUNT(CASE WHEN BA.battle_score < 0.3 THEN 1 END) as very_hard_matchups,
        -- TM dependency analysis
        COUNT(CASE WHEN BA.player_move_single_use_tm = 1 AND BA.battle_score >= 0.6 THEN 1 END) as tm_dependent_solutions,
        COUNT(CASE WHEN BA.player_move_single_use_tm = 0 AND BA.battle_score >= 0.6 THEN 1 END) as natural_solutions
    FROM {{ ref('int_battle_analysis') }} BA
    GROUP BY BA.game_stage, BA.trainer, BA.is_gym_leader
),

trainer_pokemon_analysis AS (
    -- Analyze individual pokemon difficulty within each trainer
    SELECT 
        BA.game_stage,
        BA.trainer,
        BA.trainer_pkmn_id,
        BA.trainer_pokemon,
        COUNT(DISTINCT BA.player_pkmn_id) as total_matchups,
        AVG(BA.battle_score) as avg_matchup_score,
        MIN(BA.battle_score) as worst_matchup_score,
        MAX(BA.battle_score) as best_matchup_score,
        COUNT(CASE WHEN BA.battle_score >= 0.6 THEN 1 END) as solid_counters,
        COUNT(CASE WHEN BA.battle_score < 0.4 THEN 1 END) as poor_matchups,
        -- Most effective counter
        FIRST_VALUE(BA.player_pokemon) OVER(
            PARTITION BY BA.trainer_pkmn_id 
            ORDER BY BA.battle_score DESC
        ) as best_counter_pokemon,
        FIRST_VALUE(BA.battle_score) OVER(
            PARTITION BY BA.trainer_pkmn_id 
            ORDER BY BA.battle_score DESC
        ) as best_counter_score
    FROM {{ ref('int_battle_analysis') }} BA
    GROUP BY BA.game_stage, BA.trainer, BA.trainer_pkmn_id, BA.trainer_pokemon, BA.player_pokemon, BA.battle_score
    QUALIFY ROW_NUMBER() OVER(PARTITION BY BA.trainer_pkmn_id ORDER BY BA.battle_score DESC) = 1
),

difficulty_classification AS (
    -- Classify trainer difficulty using multiple criteria
    SELECT 
        TBD.*,
        -- Primary difficulty rating
        CASE
            WHEN TBD.avg_battle_score < 0.25 THEN 'Extreme'
            WHEN TBD.avg_battle_score < 0.35 THEN 'Very Hard'
            WHEN TBD.avg_battle_score < 0.5 THEN 'Hard'
            WHEN TBD.avg_battle_score < 0.65 THEN 'Medium'
            WHEN TBD.excellent_counters <= 2 AND TBD.good_counters <= 5 THEN 'Requires Specific Counter'
            ELSE 'Easy'
        END as difficulty_rating,
        -- Secondary characteristics
        CASE 
            WHEN TBD.tm_dependent_solutions > TBD.natural_solutions THEN 'TM-Dependent'
            WHEN TBD.excellent_counters = 0 THEN 'No Easy Counters'
            WHEN TBD.very_hard_matchups > TBD.total_pokemon / 2 THEN 'Limited Options'
            WHEN TBD.min_battle_score < 0.2 THEN 'Has Brutal Pokemon'
            ELSE 'Standard'
        END as difficulty_characteristics,
        -- Priority level for team building
        CASE 
            WHEN TBD.is_gym_leader = 1 AND TBD.avg_battle_score < 0.4 THEN 'Critical Priority'
            WHEN TBD.is_gym_leader = 1 THEN 'High Priority'
            WHEN TBD.avg_battle_score < 0.3 THEN 'High Priority'
            WHEN TBD.avg_battle_score < 0.5 THEN 'Medium Priority'
            ELSE 'Low Priority'
        END as team_building_priority,
        -- Numerical difficulty score (0-10 scale)
        ROUND(
            (
                (1 - TBD.avg_battle_score) * 4 +  -- Base difficulty (0-4 points)
                CASE WHEN TBD.excellent_counters = 0 THEN 2 ELSE 0 END +  -- No excellent counters
                CASE WHEN TBD.good_counters <= 2 THEN 1 ELSE 0 END +  -- Few good counters
                CASE WHEN TBD.is_gym_leader = 1 THEN 1 ELSE 0 END +  -- Gym leader bonus
                CASE WHEN TBD.tm_dependent_solutions > TBD.natural_solutions THEN 1 ELSE 0 END +  -- TM dependency
                CASE WHEN TBD.min_battle_score < 0.2 THEN 1 ELSE 0 END  -- Brutal pokemon penalty
            ), 1
        ) as difficulty_score
    FROM trainer_battle_difficulty TBD
),

game_stage_difficulty AS (
    -- Analyze overall difficulty progression through the game
    SELECT 
        game_stage,
        COUNT(*) as total_trainers,
        COUNT(CASE WHEN is_gym_leader = 1 THEN 1 END) as gym_leaders,
        AVG(difficulty_score) as avg_stage_difficulty,
        MAX(difficulty_score) as hardest_trainer_score,
        COUNT(CASE WHEN difficulty_rating IN ('Very Hard', 'Extreme') THEN 1 END) as very_hard_trainers,
        COUNT(CASE WHEN team_building_priority = 'Critical Priority' THEN 1 END) as critical_priority_trainers,
        -- Stage difficulty classification
        CASE 
            WHEN AVG(difficulty_score) >= 7 THEN 'Brutal Stage'
            WHEN AVG(difficulty_score) >= 5.5 THEN 'Hard Stage'
            WHEN AVG(difficulty_score) >= 4 THEN 'Medium Stage'
            ELSE 'Easy Stage'
        END as stage_difficulty_rating
    FROM difficulty_classification
    GROUP BY game_stage
),

team_building_recommendations AS (
    -- Generate specific team building recommendations
    SELECT 
        DC.game_stage,
        DC.trainer,
        DC.difficulty_rating,
        DC.difficulty_score,
        DC.team_building_priority,
        DC.difficulty_characteristics,
        DC.is_gym_leader,
        DC.excellent_counters,
        DC.good_counters,
        DC.tm_dependent_solutions,
        DC.natural_solutions,
        GSD.stage_difficulty_rating,
        -- Specific recommendations
        CASE 
            WHEN DC.difficulty_rating = 'Extreme' 
            THEN 'Consider overleveling or specific team compositions'
            WHEN DC.difficulty_rating = 'Very Hard' AND DC.tm_dependent_solutions > 0
            THEN 'Allocate premium TMs for this fight'
            WHEN DC.difficulty_rating = 'Very Hard'
            THEN 'Requires careful pokemon selection and strategy'
            WHEN DC.difficulty_rating = 'Requires Specific Counter'
            THEN 'Ensure team includes one of the effective counters'
            WHEN DC.difficulty_rating = 'Hard' AND DC.is_gym_leader = 1
            THEN 'Key progression blocker - prepare thoroughly'
            ELSE 'Standard preparation sufficient'
        END as preparation_recommendation,
        -- Counter recommendations
        STRING_AGG(
            TPA.trainer_pokemon || ' (vs ' || TPA.best_counter_pokemon || ')', 
            '; '
        ) as specific_counter_suggestions
    FROM difficulty_classification DC
    LEFT JOIN game_stage_difficulty GSD ON DC.game_stage = GSD.game_stage
    LEFT JOIN trainer_pokemon_analysis TPA ON DC.trainer = TPA.trainer
    GROUP BY 
        DC.game_stage, DC.trainer, DC.difficulty_rating, DC.difficulty_score,
        DC.team_building_priority, DC.difficulty_characteristics, DC.is_gym_leader,
        DC.excellent_counters, DC.good_counters, DC.tm_dependent_solutions,
        DC.natural_solutions, GSD.stage_difficulty_rating
)

SELECT 
    game_stage,
    trainer,
    difficulty_rating,
    difficulty_score,
    team_building_priority,
    difficulty_characteristics,
    stage_difficulty_rating,
    is_gym_leader,
    excellent_counters,
    good_counters,
    tm_dependent_solutions,
    natural_solutions,
    preparation_recommendation,
    specific_counter_suggestions,
    -- Overall assessment
    CASE 
        WHEN difficulty_score >= 8 THEN 'Expect multiple attempts - this is a major difficulty spike'
        WHEN difficulty_score >= 6 THEN 'Challenging fight - thorough preparation recommended'
        WHEN difficulty_score >= 4 THEN 'Moderate difficulty - standard team should handle'
        ELSE 'Routine encounter'
    END as overall_assessment,
    -- Sort priority for planning
    ROW_NUMBER() OVER(ORDER BY 
        CASE team_building_priority 
            WHEN 'Critical Priority' THEN 1
            WHEN 'High Priority' THEN 2  
            WHEN 'Medium Priority' THEN 3
            ELSE 4
        END,
        difficulty_score DESC
    ) as planning_priority_rank
FROM team_building_recommendations
ORDER BY planning_priority_rank