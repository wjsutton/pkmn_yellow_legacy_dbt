-- mart_team_performance: Merge pokemon performance scoring, trainer difficulty analysis, and TM assignments
-- Absorbs int_trainer_difficulty logic + opt_pokemon_performance_by_stage + opt_tm_assignments

-- === Trainer Difficulty (formerly int_trainer_difficulty) ===
WITH trainer_battle_difficulty AS (
    SELECT
        BA.game_stage,
        BA.trainer,
        BA.is_mini_boss,
        COUNT(DISTINCT BA.trainer_pkmn_id) as total_pokemon,
        COUNT(DISTINCT BA.player_pkmn_id) as available_counters,
        AVG(BA.battle_score) as avg_battle_score,
        MIN(BA.battle_score) as min_battle_score,
        MAX(BA.battle_score) as max_battle_score,
        COUNT(CASE WHEN BA.battle_score >= 0.8 THEN 1 END) as excellent_counters,
        COUNT(CASE WHEN BA.battle_score >= 0.6 THEN 1 END) as good_counters,
        COUNT(CASE WHEN BA.battle_score < 0.3 THEN 1 END) as very_hard_matchups,
        COUNT(CASE WHEN BA.player_move_single_use_tm = 1 AND BA.battle_score >= 0.6 THEN 1 END) as tm_dependent_solutions,
        COUNT(CASE WHEN BA.player_move_single_use_tm = 0 AND BA.battle_score >= 0.6 THEN 1 END) as natural_solutions
    FROM {{ ref('mart_battle_outcomes') }} BA
    GROUP BY BA.game_stage, BA.trainer, BA.is_mini_boss
),

difficulty_classification AS (
    SELECT
        TBD.*,
        {{ trainer_difficulty_rating(prefix='TBD.') }} as difficulty_rating,
        {{ trainer_difficulty_score(prefix='TBD.') }} as difficulty_score
    FROM trainer_battle_difficulty TBD
),

-- === Pokemon Performance by Stage (formerly opt_pokemon_performance_by_stage) ===
battle_matchups AS (
    SELECT
        BA.game_stage,
        BA.player_pkmn_id,
        BA.player_pokemon,
        BA.trainer,
        BA.trainer_pkmn_id,
        BA.trainer_pokemon,
        BA.is_mini_boss,
        BA.battle_score,
        BA.player_pkmn_move,
        BA.player_move_single_use_tm,
        DR.difficulty_score,
        DR.difficulty_rating,
        ROW_NUMBER() OVER(
            PARTITION BY BA.player_pkmn_id, BA.trainer_pkmn_id
            ORDER BY BA.battle_score DESC
        ) as move_rank
    FROM {{ ref('mart_battle_outcomes') }} BA
    LEFT JOIN difficulty_classification DR
        ON BA.trainer = DR.trainer
),

best_matchups AS (
    SELECT *
    FROM battle_matchups
    WHERE move_rank = 1
),

best_team_options AS (
    SELECT
        BM.*,
        ROW_NUMBER() OVER(
            PARTITION BY BM.game_stage, BM.trainer_pkmn_id
            ORDER BY BM.battle_score DESC
        ) as team_rank
    FROM best_matchups BM
),

team_contributions AS (
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
        BTO.is_mini_boss,
        BTO.player_pkmn_move,
        BTO.player_move_single_use_tm,
        BTO.team_rank,
        CASE
            WHEN BTO.is_mini_boss = 1 THEN BTO.difficulty_score * 3.0
            WHEN BTO.difficulty_rating IN ('Very Hard', 'Extreme') THEN BTO.difficulty_score * 2.0
            ELSE BTO.difficulty_score
        END as battle_weight,
        CASE
            WHEN BTO.team_rank = 1 THEN BTO.battle_score *
                CASE
                    WHEN BTO.is_mini_boss = 1 THEN BTO.difficulty_score * 3.0
                    WHEN BTO.difficulty_rating IN ('Very Hard', 'Extreme') THEN BTO.difficulty_score * 2.0
                    ELSE BTO.difficulty_score
                END
            ELSE 0
        END as weighted_contribution,
        -- Baseline score for all pokemon (used to fill remaining team slots)
        BTO.battle_score *
            CASE
                WHEN BTO.is_mini_boss = 1 THEN BTO.difficulty_score * 3.0
                WHEN BTO.difficulty_rating IN ('Very Hard', 'Extreme') THEN BTO.difficulty_score * 2.0
                ELSE BTO.difficulty_score
            END as baseline_contribution,
        -- Normalize per trainer: divide by trainer roster size so each trainer
        -- contributes one "unit" of score regardless of how many pokemon they have.
        -- Without this, a trainer with 4 pokemon generates 4x the score of a
        -- trainer with 1 pokemon, drowning out hard bosses like Lt. Surge.
        (BTO.battle_score *
            CASE
                WHEN BTO.is_mini_boss = 1 THEN BTO.difficulty_score * 3.0
                WHEN BTO.difficulty_rating IN ('Very Hard', 'Extreme') THEN BTO.difficulty_score * 2.0
                ELSE BTO.difficulty_score
            END)
        / COUNT(*) OVER (PARTITION BY BTO.game_stage, BTO.player_pkmn_id, BTO.trainer)
        as normalized_contribution
    FROM best_team_options BTO
),

stage_scores AS (
    SELECT
        game_stage,
        player_pkmn_id,
        player_pokemon,
        SUM(weighted_contribution) as team_contribution_score,
        SUM(normalized_contribution) as backup_score,
        SUM(baseline_contribution) as raw_backup_score,
        SUM(battle_score) as base_score,
        0 as total_penalty,
        SUM(weighted_contribution) as route_score,
        COUNT(CASE WHEN team_rank = 1 AND player_move_single_use_tm = 1 THEN 1 END) as tm_dependent_wins,
        COUNT(CASE WHEN team_rank = 1 THEN 1 END) as battles_as_best_option,
        COUNT(*) as total_matchups,
        COUNT(CASE WHEN is_mini_boss = 1 AND team_rank = 1 THEN 1 END) as mini_boss_best_matchups,
        AVG(CASE WHEN is_mini_boss = 1 AND team_rank = 1 THEN battle_score END) as avg_mini_boss_score
    FROM team_contributions
    GROUP BY game_stage, player_pkmn_id, player_pokemon
),

pokemon_stage_performance AS (
    SELECT
        game_stage,
        player_pkmn_id,
        player_pokemon,
        route_score,
        backup_score,
        base_score,
        total_penalty,
        tm_dependent_wins,
        battles_as_best_option,
        total_matchups,
        mini_boss_best_matchups,
        avg_mini_boss_score,
        backup_score as team_selection_score,
        {{ calculate_performance_tier('backup_score', 'pokemon') }} as performance_tier,
        {{ calculate_tm_efficiency_rating('tm_dependent_wins', 'pokemon') }} as tm_efficiency,
        ROW_NUMBER() OVER(
            PARTITION BY game_stage
            ORDER BY team_contribution_score DESC, backup_score DESC, avg_mini_boss_score DESC NULLS LAST
        ) as stage_rank
    FROM stage_scores
),

-- === TM Assignments (formerly opt_tm_assignments) ===
team_candidates AS (
    SELECT
        game_stage,
        player_pkmn_id,
        player_pokemon,
        stage_rank
    FROM pokemon_stage_performance
    WHERE stage_rank <= 12
),

tm_battle_data AS (
    SELECT
        BA.game_stage,
        BA.player_pkmn_id,
        BA.player_pokemon,
        BA.player_pkmn_move as tm_move,
        BA.battle_score,
        ROW_NUMBER() OVER(
            PARTITION BY BA.player_pkmn_id, BA.trainer_pkmn_id
            ORDER BY BA.battle_score DESC
        ) as move_rank
    FROM {{ ref('mart_battle_outcomes') }} BA
    INNER JOIN team_candidates TC ON BA.player_pkmn_id = TC.player_pkmn_id
        AND BA.game_stage = TC.game_stage
    WHERE BA.player_move_single_use_tm = 1
),

pokemon_tm_scores AS (
    SELECT
        game_stage,
        player_pkmn_id,
        player_pokemon,
        tm_move,
        AVG(battle_score) as avg_battle_score,
        COUNT(*) as matchup_count
    FROM tm_battle_data
    WHERE move_rank = 1
    GROUP BY game_stage, player_pkmn_id, player_pokemon, tm_move
),

tm_rankings AS (
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
    SELECT
        game_stage,
        tm_move,
        player_pkmn_id as assigned_to_pkmn_id,
        player_pokemon as assigned_to_pokemon,
        avg_battle_score as assignment_score,
        COUNT(*) OVER(PARTITION BY game_stage, tm_move) as total_users,
        CASE
            WHEN COUNT(*) OVER(PARTITION BY game_stage, tm_move) > 1 THEN 1
            ELSE 0
        END as has_conflict
    FROM tm_rankings
    WHERE tm_rank = 1
),

pokemon_tm_loadouts AS (
    SELECT
        PTS.game_stage,
        PTS.player_pkmn_id,
        PTS.player_pokemon,
        COUNT(TA.tm_move) as tms_allocated,
        COUNT(PTS.tm_move) - COUNT(TA.tm_move) as tms_denied,
        MAX(CASE WHEN TA.tm_move IS NOT NULL THEN TA.tm_move END) as assigned_tm_move,
        LISTAGG(TA.tm_move, ', ') as allocated_tm_list
    FROM pokemon_tm_scores PTS
    LEFT JOIN tm_assignments TA ON PTS.game_stage = TA.game_stage
        AND PTS.player_pkmn_id = TA.assigned_to_pkmn_id
        AND PTS.tm_move = TA.tm_move
    GROUP BY PTS.game_stage, PTS.player_pkmn_id, PTS.player_pokemon
)

-- === Final Output: Combined Performance + TM Assignments ===
SELECT
    PSP.game_stage,
    PSP.player_pkmn_id,
    PSP.player_pokemon,
    PSP.team_selection_score,
    PSP.route_score,
    PSP.backup_score,
    PSP.base_score,
    PSP.total_penalty,
    PSP.performance_tier,
    PSP.tm_efficiency,
    PSP.tm_dependent_wins,
    PSP.battles_as_best_option,
    PSP.total_matchups,
    PSP.mini_boss_best_matchups,
    PSP.avg_mini_boss_score,
    PSP.stage_rank,
    CASE
        WHEN PSP.stage_rank <= 6 THEN 'Core Team Candidate'
        WHEN PSP.stage_rank <= 12 THEN 'Backup Option'
        ELSE 'Situational Use'
    END as team_recommendation,
    -- TM assignment data
    COALESCE(TM.assigned_tm_move, 'None') as assigned_tm_move,
    COALESCE(TM.tms_allocated, 0) as tms_allocated,
    COALESCE(TM.tms_denied, 0) as tms_denied,
    COALESCE(TM.allocated_tm_list, 'None') as allocated_tm_list,
    {{ calculate_tm_efficiency_rating('COALESCE(TM.tms_allocated, 0)', 'allocation') }} as tm_allocation_efficiency,
    {{ calculate_tm_usage_recommendation('COALESCE(TM.tms_allocated, 0)') }} as tm_usage_recommendation
FROM pokemon_stage_performance PSP
LEFT JOIN pokemon_tm_loadouts TM
    ON PSP.game_stage = TM.game_stage AND PSP.player_pkmn_id = TM.player_pkmn_id
ORDER BY PSP.game_stage, PSP.stage_rank
