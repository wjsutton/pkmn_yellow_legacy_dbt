-- mart_recommended_teams: Variant-aware team selection.
-- Uses base scores from mart_team_performance (computed against ALL trainers),
-- then subtracts contributions from excluded rival trainers per variant.
-- This avoids reprocessing battle data while making rival type affect team selection.

WITH run_variants AS (
    {{ generate_run_variants(ref('mart_team_performance')) }}
),

-- === Compute rival-trainer contributions to subtract per variant ===
-- Only process rival-specific battles (tiny fraction of total data)
rival_battles AS (
    SELECT
        bo.game_stage,
        bo.player_pkmn_id,
        bo.player_pokemon,
        bo.trainer,
        bo.trainer_pkmn_id,
        bo.is_mini_boss,
        bo.battle_score,
        bo.player_pkmn_move,
        bo.player_move_single_use_tm
    FROM {{ ref('mart_battle_outcomes') }} bo
    WHERE bo.trainer LIKE '%\_Flareon' ESCAPE '\'
       OR bo.trainer LIKE '%\_Vaporeon' ESCAPE '\'
       OR bo.trainer LIKE '%\_Jolteon' ESCAPE '\'
       OR bo.trainer IN ('Rival_1', 'Rival_2')
),

-- Best move per (player_pkmn, rival_trainer_pkmn)
rival_best_moves AS (
    SELECT *
    FROM (
        SELECT
            rb.*,
            ROW_NUMBER() OVER(
                PARTITION BY rb.player_pkmn_id, rb.trainer_pkmn_id
                ORDER BY rb.battle_score DESC
            ) as move_rank
        FROM rival_battles rb
    )
    WHERE move_rank = 1
),

-- Rival trainer difficulty (same formula as mart_team_performance)
rival_trainer_difficulty AS (
    SELECT
        game_stage,
        trainer,
        is_mini_boss,
        AVG(battle_score) as avg_battle_score,
        MIN(battle_score) as min_battle_score,
        COUNT(CASE WHEN battle_score >= 0.8 THEN 1 END) as excellent_counters,
        COUNT(CASE WHEN battle_score >= 0.6 THEN 1 END) as good_counters,
        COUNT(CASE WHEN player_move_single_use_tm = 1 AND battle_score >= 0.6 THEN 1 END) as tm_dependent_solutions,
        COUNT(CASE WHEN player_move_single_use_tm = 0 AND battle_score >= 0.6 THEN 1 END) as natural_solutions
    FROM rival_best_moves
    GROUP BY game_stage, trainer, is_mini_boss
),

rival_difficulty_class AS (
    SELECT
        *,
        {{ trainer_difficulty_rating() }} as difficulty_rating,
        {{ trainer_difficulty_score() }} as difficulty_score
    FROM rival_trainer_difficulty
),

-- Best counter rank per rival trainer pokemon
rival_team_options AS (
    SELECT
        rbm.*,
        ROW_NUMBER() OVER(
            PARTITION BY rbm.game_stage, rbm.trainer_pkmn_id
            ORDER BY rbm.battle_score DESC
        ) as team_rank
    FROM rival_best_moves rbm
),

-- Rival contributions with difficulty weights
rival_contributions AS (
    SELECT
        rto.game_stage,
        rto.player_pkmn_id,
        rto.player_pokemon,
        rto.trainer,
        rto.team_rank,
        -- Normalized contribution (same formula as mart_team_performance)
        (rto.battle_score *
            CASE
                WHEN rto.is_mini_boss = 1 THEN dc.difficulty_score * 3.0
                WHEN dc.difficulty_rating IN ('Very Hard', 'Extreme') THEN dc.difficulty_score * 2.0
                ELSE dc.difficulty_score
            END)
        / COUNT(*) OVER (PARTITION BY rto.game_stage, rto.player_pkmn_id, rto.trainer)
        as normalized_contribution,
        -- Weighted contribution (best counter only)
        CASE
            WHEN rto.team_rank = 1 THEN rto.battle_score *
                CASE
                    WHEN rto.is_mini_boss = 1 THEN dc.difficulty_score * 3.0
                    WHEN dc.difficulty_rating IN ('Very Hard', 'Extreme') THEN dc.difficulty_score * 2.0
                    ELSE dc.difficulty_score
                END
            ELSE 0
        END as weighted_contribution
    FROM rival_team_options rto
    LEFT JOIN rival_difficulty_class dc
        ON dc.game_stage = rto.game_stage
        AND dc.trainer = rto.trainer
),

-- Sum excluded contributions per pokemon per variant
-- Each variant excludes different rival trainers
rival_exclusion_scores AS (
    SELECT
        game_stage,
        player_pkmn_id,
        -- Jolteon variant: exclude trainers matching %_Flareon or %_Vaporeon
        SUM(CASE WHEN trainer LIKE '%\_Flareon' ESCAPE '\' OR trainer LIKE '%\_Vaporeon' ESCAPE '\'
            THEN normalized_contribution ELSE 0 END) as jolteon_exclude_backup,
        SUM(CASE WHEN trainer LIKE '%\_Flareon' ESCAPE '\' OR trainer LIKE '%\_Vaporeon' ESCAPE '\'
            THEN weighted_contribution ELSE 0 END) as jolteon_exclude_weighted,
        -- Flareon variant: exclude %_Jolteon, %_Vaporeon, and Rival_2
        SUM(CASE WHEN trainer LIKE '%\_Jolteon' ESCAPE '\' OR trainer LIKE '%\_Vaporeon' ESCAPE '\' OR trainer = 'Rival_2'
            THEN normalized_contribution ELSE 0 END) as flareon_exclude_backup,
        SUM(CASE WHEN trainer LIKE '%\_Jolteon' ESCAPE '\' OR trainer LIKE '%\_Vaporeon' ESCAPE '\' OR trainer = 'Rival_2'
            THEN weighted_contribution ELSE 0 END) as flareon_exclude_weighted,
        -- Vaporeon variant: exclude %_Flareon, %_Jolteon, Rival_1, and Rival_2
        SUM(CASE WHEN trainer LIKE '%\_Flareon' ESCAPE '\' OR trainer LIKE '%\_Jolteon' ESCAPE '\' OR trainer IN ('Rival_1', 'Rival_2')
            THEN normalized_contribution ELSE 0 END) as vaporeon_exclude_backup,
        SUM(CASE WHEN trainer LIKE '%\_Flareon' ESCAPE '\' OR trainer LIKE '%\_Jolteon' ESCAPE '\' OR trainer IN ('Rival_1', 'Rival_2')
            THEN weighted_contribution ELSE 0 END) as vaporeon_exclude_weighted
    FROM rival_contributions
    GROUP BY game_stage, player_pkmn_id
),

-- === Base pokemon performance with variant-adjusted scores ===
-- Split into two CTEs: raw scores first, then macro-derived columns
pokemon_performance_raw AS (
    SELECT
        TP.game_stage,
        TP.player_pkmn_id,
        TP.player_pokemon,
        -- Variant-adjusted scores: base minus excluded rival contributions
        TP.team_selection_score
            - CASE rv.rival_type
                WHEN 'Jolteon'  THEN COALESCE(res.jolteon_exclude_backup, 0)
                WHEN 'Flareon'  THEN COALESCE(res.flareon_exclude_backup, 0)
                WHEN 'Vaporeon' THEN COALESCE(res.vaporeon_exclude_backup, 0)
            END as team_selection_score,
        TP.tms_allocated,
        TP.tms_denied,
        COALESCE(TP.assigned_tm_move, 'None') as assigned_tm_move,
        TP.tm_allocation_efficiency as tm_efficiency_rating,
        -- Variant-adjusted contribution score for ranking
        (TP.route_score
            - CASE rv.rival_type
                WHEN 'Jolteon'  THEN COALESCE(res.jolteon_exclude_weighted, 0)
                WHEN 'Flareon'  THEN COALESCE(res.flareon_exclude_weighted, 0)
                WHEN 'Vaporeon' THEN COALESCE(res.vaporeon_exclude_weighted, 0)
            END) as team_contribution_score,
        TP.avg_mini_boss_score,
        CASE WHEN {{ is_legendary('TP.player_pokemon') }} THEN 1 ELSE 0 END as is_legendary,
        CASE WHEN TP.player_pkmn_id = 'Player_Pikachu_1' THEN 1 ELSE 0 END as is_pikachu,
        rv.run_name,
        rv.rival_type,
        rv.keep_pikachu,
        rv.no_legends,
        rv.exclude_rival_patterns,
        rv.exclude_trainers
    FROM {{ ref('mart_team_performance') }} TP
    CROSS JOIN run_variants rv
    LEFT JOIN rival_exclusion_scores res
        ON res.game_stage = TP.game_stage
        AND res.player_pkmn_id = TP.player_pkmn_id
    WHERE rv.game_stage = TP.game_stage
),

pokemon_performance_base AS (
    SELECT
        ppr.*,
        {{ calculate_performance_tier('ppr.team_selection_score', 'pokemon') }} as performance_tier,
        CASE
            WHEN ppr.tms_denied > 0 THEN ppr.team_selection_score * 0.8
            ELSE ppr.team_selection_score
        END as adjusted_team_score
    FROM pokemon_performance_raw ppr
),

{{ collapse_evolution_chains('pokemon_performance_base', 'player_pokemon', 'game_stage') }}

filtered_pokemon AS (
    SELECT *
    FROM pokemon_performance_base_deduped
    WHERE (no_legends = 0 OR is_legendary = 0)
),

team_selections AS (
    SELECT
        *,
        ROW_NUMBER() OVER(
            PARTITION BY run_name, game_stage
            ORDER BY
                CASE WHEN keep_pikachu = 1 AND is_pikachu = 1 THEN 0 ELSE 1 END,
                adjusted_team_score DESC
        ) as team_rank
    FROM filtered_pokemon
),

final_teams AS (
    SELECT
        *,
        COUNT(*) OVER(PARTITION BY run_name, game_stage) as team_size,
        AVG(adjusted_team_score) OVER(PARTITION BY run_name, game_stage) as avg_team_score,
        SUM(tms_allocated) OVER(PARTITION BY run_name, game_stage) as total_team_tms
    FROM team_selections
    WHERE team_rank <= 6
),

team_metadata AS (
    SELECT
        run_name,
        game_stage,
        avg_team_score as team_performance_score,
        total_team_tms,
        team_size,
        {{ calculate_performance_tier('avg_team_score', 'team') }} as team_quality,
        {{ calculate_tm_efficiency_rating('total_team_tms', 'team') }} as tm_investment_level
    FROM (
        SELECT DISTINCT
            run_name, game_stage,
            avg_team_score, total_team_tms, team_size
        FROM final_teams
    ) t
)

SELECT
    FT.run_name,
    FT.game_stage,
    FT.rival_type,
    FT.keep_pikachu,
    FT.no_legends,
    FT.exclude_rival_patterns,
    FT.exclude_trainers,
    FT.player_pkmn_id,
    FT.player_pokemon,
    FT.team_rank,
    FT.adjusted_team_score as pokemon_score,
    FT.performance_tier,
    FT.tm_efficiency_rating,
    FT.assigned_tm_move,
    FT.tms_allocated,
    FT.is_pikachu,
    TM.team_performance_score,
    TM.team_quality,
    TM.tm_investment_level,
    TM.total_team_tms,
    CASE
        WHEN FT.team_rank = 1 THEN 'Primary team member'
        WHEN FT.team_rank <= 3 THEN 'Core team member'
        ELSE 'Support team member'
    END as role_on_team,
    EN.evolution_note,
    {{ generate_variant_description('FT.rival_type', 'FT.keep_pikachu', 'FT.no_legends') }} as variant_description
FROM final_teams FT
INNER JOIN team_metadata TM ON FT.run_name = TM.run_name
    AND FT.game_stage = TM.game_stage
LEFT JOIN _evo_notes EN ON EN.pokemon = FT.player_pokemon
ORDER BY FT.run_name, FT.game_stage, FT.team_rank
