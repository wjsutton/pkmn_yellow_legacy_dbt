WITH battle_performance AS (
    -- Get battle performance for each pokemon against each trainer
    SELECT 
        BA.game_stage,
        BA.player_pkmn_id,
        BA.player_pokemon,
        BA.trainer,
        BA.trainer_pkmn_id,
        BA.trainer_pokemon,
        BA.is_gym_leader,
        BA.battle_score,
        BA.player_move_single_use_tm,
        BA.player_pkmn_move,
        -- Weight gym leaders more heavily
        CASE WHEN BA.is_gym_leader = 1 THEN BA.battle_score * 2 ELSE BA.battle_score END as weighted_battle_score,
        ROW_NUMBER() OVER(
            PARTITION BY BA.player_pkmn_id, BA.trainer_pkmn_id 
            ORDER BY BA.battle_score DESC
        ) as move_rank
    FROM {{ ref('int_battle_analysis') }} BA
),

pokemon_overall_performance AS (
    -- Calculate overall performance metrics for each pokemon
    SELECT 
        game_stage,
        player_pkmn_id,
        player_pokemon,
        COUNT(DISTINCT trainer_pkmn_id) as total_matchups,
        COUNT(DISTINCT CASE WHEN is_gym_leader = 1 THEN trainer_pkmn_id END) as gym_leader_matchups,
        AVG(battle_score) as avg_battle_score,
        AVG(weighted_battle_score) as avg_weighted_battle_score,
        SUM(battle_score) as total_battle_score,
        SUM(weighted_battle_score) as total_weighted_battle_score,
        -- Performance tiers
        COUNT(CASE WHEN battle_score >= 0.8 THEN 1 END) as excellent_matchups,
        COUNT(CASE WHEN battle_score >= 0.6 THEN 1 END) as good_matchups,
        COUNT(CASE WHEN battle_score >= 0.4 THEN 1 END) as decent_matchups,
        COUNT(CASE WHEN battle_score < 0.3 THEN 1 END) as poor_matchups,
        -- TM dependency analysis
        COUNT(CASE WHEN player_move_single_use_tm = 1 THEN 1 END) as tm_dependent_wins,
        COUNT(CASE WHEN player_move_single_use_tm = 0 THEN 1 END) as natural_move_wins
    FROM battle_performance
    WHERE move_rank = 1  -- Best move for each matchup
    GROUP BY game_stage, player_pkmn_id, player_pokemon
),

pokemon_type_coverage AS (
    -- Analyze type coverage and diversity
    SELECT 
        POP.game_stage,
        POP.player_pkmn_id,
        POP.player_pokemon,
        PS.type1,
        PS.type2,
        -- Count how many different opponent types this pokemon is effective against
        COUNT(DISTINCT 
            CASE WHEN BP.battle_score >= 0.6 
            THEN CONCAT(COALESCE(PS2.type1, ''), '|', COALESCE(PS2.type2, '')) 
            END
        ) as effective_against_types,
        -- Resistance analysis
        COUNT(DISTINCT 
            CASE WHEN BP.battle_score < 0.4 
            THEN CONCAT(COALESCE(PS2.type1, ''), '|', COALESCE(PS2.type2, '')) 
            END
        ) as weak_against_types
    FROM pokemon_overall_performance POP
    INNER JOIN {{ ref('stg_pkmn_stats') }} PS ON POP.player_pokemon = PS.pokemon
    INNER JOIN battle_performance BP ON POP.player_pkmn_id = BP.player_pkmn_id AND BP.move_rank = 1
    INNER JOIN {{ ref('stg_pkmn_stats') }} PS2 ON BP.trainer_pokemon = PS2.pokemon
    GROUP BY POP.game_stage, POP.player_pkmn_id, POP.player_pokemon, PS.type1, PS.type2
),

pokemon_team_scores AS (
    -- Calculate final team selection scores
    SELECT 
        POP.*,
        PTC.type1,
        PTC.type2,
        PTC.effective_against_types,
        PTC.weak_against_types,
        -- Team selection score combining multiple factors
        (
            (POP.avg_weighted_battle_score * 0.4) +
            (POP.total_weighted_battle_score / 100.0 * 0.3) +
            (PTC.effective_against_types / 10.0 * 0.2) +
            (CASE WHEN POP.tm_dependent_wins <= 2 THEN 0.1 ELSE 0.05 END) +
            (CASE WHEN POP.poor_matchups <= 2 THEN 0.05 ELSE 0.0 END)
        ) as team_selection_score,
        -- Difficulty handling capability
        CASE 
            WHEN POP.poor_matchups <= 1 AND POP.excellent_matchups >= 3 THEN 'Elite'
            WHEN POP.poor_matchups <= 2 AND POP.good_matchups >= 5 THEN 'Strong'
            WHEN POP.poor_matchups <= 3 AND POP.decent_matchups >= 7 THEN 'Solid'
            WHEN POP.poor_matchups <= 5 THEN 'Viable'
            ELSE 'Weak'
        END as pokemon_tier,
        -- TM efficiency rating
        CASE 
            WHEN POP.tm_dependent_wins = 0 THEN 'TM-Free'
            WHEN POP.tm_dependent_wins <= 2 THEN 'TM-Efficient' 
            WHEN POP.tm_dependent_wins <= 4 THEN 'TM-Dependent'
            ELSE 'TM-Heavy'
        END as tm_efficiency
    FROM pokemon_overall_performance POP
    INNER JOIN pokemon_type_coverage PTC ON POP.player_pkmn_id = PTC.player_pkmn_id
),

team_recommendations AS (
    -- Generate team recommendations for each game stage
    SELECT 
        game_stage,
        player_pkmn_id,
        player_pokemon,
        type1,
        type2,
        team_selection_score,
        pokemon_tier,
        tm_efficiency,
        avg_weighted_battle_score,
        total_weighted_battle_score,
        excellent_matchups,
        good_matchups,
        poor_matchups,
        tm_dependent_wins,
        effective_against_types,
        -- Ranking within game stage
        ROW_NUMBER() OVER(
            PARTITION BY game_stage 
            ORDER BY team_selection_score DESC, avg_weighted_battle_score DESC
        ) as team_rank,
        -- Type diversity score (for team building)
        CASE 
            WHEN type1 IN ('Normal', 'Fighting', 'Flying') THEN 'Physical'
            WHEN type1 IN ('Psychic', 'Electric', 'Fire', 'Water', 'Grass', 'Ice') THEN 'Special'
            WHEN type1 IN ('Rock', 'Ground', 'Steel') THEN 'Defensive'
            WHEN type1 IN ('Poison', 'Bug', 'Ghost', 'Dark') THEN 'Utility'
            ELSE 'Balanced'
        END as role_category
    FROM pokemon_team_scores
),

optimal_team_compositions AS (
    -- Generate optimal 6-pokemon teams with type diversity
    SELECT 
        game_stage,
        team_rank,
        player_pkmn_id,
        player_pokemon,
        type1,
        type2,
        team_selection_score,
        pokemon_tier,
        tm_efficiency,
        role_category,
        -- Team building metrics
        LAG(type1) OVER(PARTITION BY game_stage ORDER BY team_rank) as prev_type1,
        LAG(type2) OVER(PARTITION BY game_stage ORDER BY team_rank) as prev_type2,
        -- Diversity bonus (penalize type overlap)
        CASE 
            WHEN team_rank = 1 THEN 0
            WHEN type1 = LAG(type1) OVER(PARTITION BY game_stage ORDER BY team_rank) THEN -0.1
            WHEN type2 = LAG(type1) OVER(PARTITION BY game_stage ORDER BY team_rank) OR 
                 type1 = LAG(type2) OVER(PARTITION BY game_stage ORDER BY team_rank) THEN -0.05
            ELSE 0.02
        END as diversity_bonus,
        team_selection_score + 
        CASE 
            WHEN team_rank = 1 THEN 0
            WHEN type1 = LAG(type1) OVER(PARTITION BY game_stage ORDER BY team_rank) THEN -0.1
            WHEN type2 = LAG(type1) OVER(PARTITION BY game_stage ORDER BY team_rank) OR 
                 type1 = LAG(type2) OVER(PARTITION BY game_stage ORDER BY team_rank) THEN -0.05
            ELSE 0.02
        END as adjusted_team_score
    FROM team_recommendations
    WHERE team_rank <= 12  -- Consider top 12 for team building
)

SELECT 
    game_stage,
    team_rank as recommended_rank,
    player_pkmn_id,
    player_pokemon,
    type1,
    type2,
    team_selection_score,
    adjusted_team_score,
    pokemon_tier,
    tm_efficiency,
    role_category,
    diversity_bonus,
    -- Team slot recommendation
    CASE 
        WHEN team_rank <= 6 THEN 'Core Team'
        WHEN team_rank <= 9 THEN 'Backup Option'
        ELSE 'Situational Pick'
    END as team_slot_recommendation,
    -- Usage notes
    CASE 
        WHEN pokemon_tier = 'Elite' AND tm_efficiency = 'TM-Free' THEN 'Premier choice - no TM investment needed'
        WHEN pokemon_tier = 'Elite' AND tm_efficiency = 'TM-Efficient' THEN 'Premier choice - minimal TM investment'
        WHEN pokemon_tier = 'Strong' AND tm_efficiency = 'TM-Free' THEN 'Solid choice - reliable performance'
        WHEN tm_efficiency = 'TM-Heavy' THEN 'High TM cost - consider alternatives'
        WHEN pokemon_tier = 'Weak' THEN 'Avoid unless no alternatives'
        ELSE 'Good option - balanced investment'
    END as usage_recommendation
FROM optimal_team_compositions
WHERE team_rank <= 10  -- Top 10 recommendations per stage
ORDER BY game_stage, adjusted_team_score DESC