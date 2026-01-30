WITH run_variants AS (
    -- Create all 12 run variants using updated macro (3 rival types x 2 pikachu variants x 2 legendary variants)
    {{ generate_run_variants(ref('opt_team_performance')) }}
),

pokemon_performance_base AS (
    -- Get base pokemon performance with TM allocations from unified model
    SELECT
        TP.game_stage,
        TP.player_pkmn_id,
        TP.player_pokemon,
        TP.team_selection_score,
        TP.performance_tier,
        TP.stage_rank,
        TP.tms_allocated,
        COALESCE(TP.assigned_tm_move, 'None') as assigned_tm_move,
        TP.tm_allocation_efficiency as tm_efficiency_rating,
        -- Apply TM conflict penalty
        CASE
            WHEN TP.tms_denied > 0 THEN TP.team_selection_score * 0.8
            ELSE TP.team_selection_score
        END as adjusted_team_score,
        -- Check if this is a legendary pokemon
        CASE
            WHEN TP.player_pokemon IN ('Moltres', 'Articuno', 'Zapdos', 'Mewtwo', 'Mew') THEN 1
            ELSE 0
        END as is_legendary,
        -- Check if this is Pikachu
        CASE
            WHEN TP.player_pkmn_id = 'Player_Pikachu_1' THEN 1
            ELSE 0
        END as is_pikachu
    FROM {{ ref('opt_team_performance') }} TP
),

pokemon_performance AS (
    -- Apply battle filtering based on rival variants
    SELECT
        RV.game_stage,
        RV.rival_type,
        RV.run_name,
        RV.keep_pikachu,
        RV.no_legends,
        RV.exclude_rival_patterns,
        RV.exclude_trainers,
        PPB.player_pkmn_id,
        PPB.player_pokemon,
        PPB.performance_tier,
        PPB.stage_rank,
        PPB.tms_allocated,
        PPB.assigned_tm_move,
        PPB.tm_efficiency_rating,
        PPB.is_legendary,
        PPB.is_pikachu,
        PPB.adjusted_team_score
    FROM run_variants RV
    CROSS JOIN pokemon_performance_base PPB
    WHERE RV.game_stage = PPB.game_stage
),

filtered_pokemon AS (
    -- Apply variant filters (NoLedges filtering for legendary pokemon)
    SELECT
        PP.game_stage,
        PP.rival_type,
        PP.run_name,
        PP.keep_pikachu,
        PP.no_legends,
        PP.exclude_rival_patterns,
        PP.exclude_trainers,
        PP.player_pkmn_id,
        PP.player_pokemon,
        PP.performance_tier,
        PP.stage_rank,
        PP.tms_allocated,
        PP.assigned_tm_move,
        PP.tm_efficiency_rating,
        PP.is_legendary,
        PP.is_pikachu,
        PP.adjusted_team_score
    FROM pokemon_performance PP
    WHERE (PP.no_legends = 0 OR PP.is_legendary = 0)
),

team_selections AS (
    -- Select optimal teams based on variant rules
    SELECT
        game_stage,
        rival_type,
        run_name,
        keep_pikachu,
        no_legends,
        exclude_rival_patterns,
        exclude_trainers,
        player_pkmn_id,
        player_pokemon,
        adjusted_team_score,
        performance_tier,
        tm_efficiency_rating,
        assigned_tm_move,
        tms_allocated,
        is_pikachu,
        -- Rank pokemon for team selection
        CASE
            WHEN keep_pikachu = 1 AND is_pikachu = 1 THEN 1
            WHEN keep_pikachu = 1 AND is_pikachu = 0 THEN
                ROW_NUMBER() OVER(
                    PARTITION BY run_name, game_stage
                    ORDER BY adjusted_team_score DESC
                ) + 1
            ELSE
                ROW_NUMBER() OVER(
                    PARTITION BY run_name, game_stage
                    ORDER BY adjusted_team_score DESC
                )
        END as team_rank
    FROM filtered_pokemon
),

final_teams AS (
    -- Select final 6-pokemon teams
    SELECT
        game_stage,
        rival_type,
        run_name,
        keep_pikachu,
        no_legends,
        exclude_rival_patterns,
        exclude_trainers,
        player_pkmn_id,
        player_pokemon,
        adjusted_team_score,
        performance_tier,
        tm_efficiency_rating,
        assigned_tm_move,
        tms_allocated,
        team_rank,
        is_pikachu,
        COUNT(*) OVER(PARTITION BY run_name, game_stage) as team_size,
        AVG(adjusted_team_score) OVER(PARTITION BY run_name, game_stage) as avg_team_score,
        SUM(tms_allocated) OVER(PARTITION BY run_name, game_stage) as total_team_tms
    FROM team_selections
    WHERE team_rank <= 6
),

team_metadata AS (
    SELECT
        game_stage,
        rival_type,
        run_name,
        keep_pikachu,
        no_legends,
        avg_team_score as team_performance_score,
        total_team_tms,
        team_size,
        {{ calculate_performance_tier('avg_team_score', 'team') }} as team_quality,
        {{ calculate_tm_efficiency_rating('total_team_tms', 'team') }} as tm_investment_level
    FROM (
        SELECT DISTINCT
            game_stage, rival_type, run_name, keep_pikachu, no_legends,
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
    {{ generate_variant_description('FT.rival_type', 'FT.keep_pikachu', 'FT.no_legends') }} as variant_description
FROM final_teams FT
INNER JOIN team_metadata TM ON FT.run_name = TM.run_name
    AND FT.game_stage = TM.game_stage
ORDER BY FT.run_name, FT.game_stage, FT.team_rank
