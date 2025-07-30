{{ config(materialized='table') }}

WITH run_variants AS (
    -- Create all run variants using macro (standard, NoLedges, with/without Pikachu)
    {{ generate_run_variants(ref('opt_pokemon_performance_by_stage')) }}
),

pokemon_performance AS (
    -- Get pokemon performance with TM allocations
    SELECT 
        PSS.game_stage,
        PSS.player_pkmn_id,
        PSS.player_pokemon,
        PSS.team_selection_score,
        PSS.performance_tier,
        PSS.stage_rank,
        COALESCE(TM.tms_allocated, 0) as tms_allocated,
        COALESCE(TM.assigned_tm_move, 'None') as assigned_tm_move,
        COALESCE(TM.tm_efficiency_rating, 'TM-Free') as tm_efficiency_rating,
        -- Apply TM conflict penalty (matches Python calculate_team_score logic)
        CASE 
            WHEN COALESCE(TM.tms_denied, 0) > 0 THEN PSS.team_selection_score * 0.8  -- 20% penalty for conflicts
            ELSE PSS.team_selection_score
        END as adjusted_team_score,
        -- Check if this is a legendary pokemon for NoLedges filtering
        CASE 
            WHEN PSS.player_pokemon IN ('Moltres', 'Articuno', 'Zapdos', 'Mewtwo', 'Mew') THEN 1
            ELSE 0
        END as is_legendary,
        -- Check if this is Pikachu
        CASE 
            WHEN PSS.player_pkmn_id = 'Player_Pikachu_1' THEN 1
            ELSE 0  
        END as is_pikachu
    FROM {{ ref('opt_pokemon_performance_by_stage') }} PSS
    LEFT JOIN {{ ref('opt_tm_assignments') }} TM 
        ON PSS.game_stage = TM.game_stage AND PSS.player_pkmn_id = TM.player_pkmn_id
),

filtered_pokemon AS (
    -- Apply variant filters (NoLedges, Pikachu variants)
    SELECT 
        RV.run_name,
        RV.keep_pikachu,
        RV.no_legends,
        PP.*
    FROM run_variants RV
    CROSS JOIN pokemon_performance PP
    WHERE RV.game_stage = PP.game_stage
        AND (RV.no_legends = 0 OR PP.is_legendary = 0)  -- Filter legendaries for NoLedges
),

team_selections AS (
    -- Select optimal teams based on variant rules
    SELECT 
        run_name,
        game_stage,
        keep_pikachu,
        no_legends,
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
            WHEN keep_pikachu = 1 AND is_pikachu = 1 THEN 1  -- Pikachu always first if keeping
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
        run_name,
        game_stage,
        keep_pikachu,
        no_legends,
        player_pkmn_id,
        player_pokemon,
        adjusted_team_score,
        performance_tier,
        tm_efficiency_rating,
        assigned_tm_move,
        tms_allocated,
        team_rank,
        is_pikachu,
        -- Team composition summary
        COUNT(*) OVER(PARTITION BY run_name, game_stage) as team_size,
        AVG(adjusted_team_score) OVER(PARTITION BY run_name, game_stage) as avg_team_score,
        SUM(tms_allocated) OVER(PARTITION BY run_name, game_stage) as total_team_tms
    FROM team_selections
    WHERE team_rank <= 6  -- Top 6 pokemon per variant
),

team_metadata AS (
    -- Calculate team-level metadata
    SELECT 
        run_name,
        game_stage,
        keep_pikachu,
        no_legends,
        avg_team_score as team_performance_score,
        total_team_tms,
        team_size,
        -- Team quality assessment
        {{ calculate_performance_tier('avg_team_score', 'team') }} as team_quality,
        -- TM investment level
        {{ calculate_tm_efficiency_rating('total_team_tms', 'team') }} as tm_investment_level
    FROM (
        SELECT DISTINCT 
            run_name, game_stage, keep_pikachu, no_legends,
            avg_team_score, total_team_tms, team_size
        FROM final_teams
    ) t
)

SELECT 
    FT.run_name,
    FT.game_stage,
    FT.keep_pikachu,
    FT.no_legends,
    FT.player_pkmn_id,
    FT.player_pokemon,
    FT.team_rank,
    FT.adjusted_team_score as pokemon_score,
    FT.performance_tier,
    FT.tm_efficiency_rating,
    FT.assigned_tm_move,
    FT.tms_allocated,
    FT.is_pikachu,
    -- Team metadata
    TM.team_performance_score,
    TM.team_quality,
    TM.tm_investment_level,
    TM.total_team_tms,
    -- Usage recommendations
    CASE 
        WHEN FT.team_rank = 1 THEN 'Primary team member'
        WHEN FT.team_rank <= 3 THEN 'Core team member'
        ELSE 'Support team member'
    END as role_on_team,
    -- Variant description
    {{ generate_variant_description('FT.keep_pikachu', 'FT.no_legends') }} as variant_description
FROM final_teams FT
INNER JOIN team_metadata TM ON FT.run_name = TM.run_name 
    AND FT.game_stage = TM.game_stage
ORDER BY FT.run_name, FT.game_stage, FT.team_rank