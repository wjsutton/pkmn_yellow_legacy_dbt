-- dash_team_builder: Combined view of recommended, backup, and min-exp teams.
-- Grain: one row per (run_name, game_stage, team_type, pokemon)

WITH run_variants AS (
    {{ generate_run_variants(ref('mart_team_performance')) }}
),

-- Recommended team (ranks 1-6, already variant-aware)
recommended AS (
    SELECT
        rt.run_name,
        rt.game_stage,
        rt.rival_type,
        rt.keep_pikachu,
        rt.no_legends,
        rt.variant_description,
        rt.player_pokemon AS pokemon,
        rt.team_rank AS slot_order,
        rt.pokemon_score,
        rt.performance_tier,
        rt.assigned_tm_move,
        rt.tms_allocated,
        rt.role_on_team,
        rt.team_performance_score,
        rt.team_quality,
        rt.evolution_note,
        'recommended' AS team_type
    FROM {{ ref('mart_recommended_teams') }} rt
),

-- Backup options: stage_rank 7+ from mart_team_performance, cross-joined with variants
-- Exclude pokemon already on the recommended team for that variant
backup_candidates AS (
    SELECT
        rv.run_name,
        rv.game_stage,
        rv.rival_type,
        rv.keep_pikachu,
        rv.no_legends,
        tp.player_pokemon AS pokemon,
        tp.stage_rank,
        tp.team_selection_score AS pokemon_score,
        tp.performance_tier,
        COALESCE(tp.assigned_tm_move, 'None') AS assigned_tm_move,
        COALESCE(tp.tms_allocated, 0) AS tms_allocated,
        {{ generate_variant_description('rv.rival_type', 'rv.keep_pikachu', 'rv.no_legends') }} AS variant_description
    FROM {{ ref('mart_team_performance') }} tp
    CROSS JOIN run_variants rv
    WHERE rv.game_stage = tp.game_stage
      AND tp.stage_rank BETWEEN 7 AND 18
      -- Filter legendaries per variant
      AND (rv.no_legends = 0 OR NOT {{ is_legendary('tp.player_pokemon') }})
      -- Exclude pokemon already on the recommended team for that variant
      AND NOT EXISTS (
          SELECT 1
          FROM {{ ref('mart_recommended_teams') }} rt
          WHERE rt.run_name = rv.run_name
            AND rt.game_stage = rv.game_stage
            AND rt.player_pokemon = tp.player_pokemon
      )
),

-- Collapse evolution chains for backups: dedup + get _evo_notes
{{ collapse_evolution_chains('backup_candidates', 'pokemon', 'game_stage') }}

backups AS (
    SELECT
        bc.run_name,
        bc.game_stage,
        bc.rival_type,
        bc.keep_pikachu,
        bc.no_legends,
        bc.variant_description,
        bc.pokemon,
        ROW_NUMBER() OVER (
            PARTITION BY bc.run_name, bc.game_stage
            ORDER BY bc.pokemon_score DESC
        ) AS slot_order,
        bc.pokemon_score,
        bc.performance_tier,
        bc.assigned_tm_move,
        bc.tms_allocated,
        'Backup option' AS role_on_team,
        NULL::DOUBLE AS team_performance_score,
        NULL::VARCHAR AS team_quality,
        en.evolution_note,
        'backup' AS team_type
    FROM backup_candidates_deduped bc
    LEFT JOIN _evo_notes en ON en.pokemon = bc.pokemon
    QUALIFY slot_order <= 6
),

-- Min-exp team (already variant-aware)
min_exp AS (
    SELECT
        mes.run_name,
        mes.game_stage,
        mes.rival_type,
        mes.keep_pikachu,
        mes.no_legends,
        mes.variant_description,
        mes.pokemon,
        mes.pick_order AS slot_order,
        NULL::DOUBLE AS pokemon_score,
        NULL::VARCHAR AS performance_tier,
        NULL::VARCHAR AS assigned_tm_move,
        0 AS tms_allocated,
        CASE
            WHEN mes.pick_order = 1 THEN 'Primary coverage'
            WHEN mes.pick_order <= 3 THEN 'Core coverage'
            ELSE 'Support coverage'
        END AS role_on_team,
        NULL::DOUBLE AS team_performance_score,
        NULL::VARCHAR AS team_quality,
        mes.evolution_note,
        'min_exp' AS team_type
    FROM {{ ref('mart_min_exp_squads') }} mes
),

-- Union all three team types
all_teams AS (
    SELECT * FROM recommended
    UNION ALL
    SELECT * FROM backups
    UNION ALL
    SELECT * FROM min_exp
),

-- EXP data from mart_stage_pokemon_costs (for recommended/backup)
exp_data_stage AS (
    SELECT
        pokemon,
        game_stage,
        fresh_exp_cost,
        is_traded,
        catch_level
    FROM {{ ref('mart_stage_pokemon_costs') }}
),

-- Min-exp has its own EXP data
min_exp_data AS (
    SELECT
        run_name,
        game_stage,
        pokemon,
        exp_needed,
        exp_earned,
        exp_deficit,
        exp_status,
        is_traded,
        coverage_pct
    FROM {{ ref('mart_min_exp_squads') }}
),

-- Catch locations with map coordinates
catch_locations AS (
    SELECT
        pa.pokemon,
        pa.game_stage,
        ml.display_name AS catch_display_name,
        pa.encounter_level AS catch_level,
        ml.x_coordinate AS catch_x,
        ml.y_coordinate AS catch_y,
        ROW_NUMBER() OVER (
            PARTITION BY pa.pokemon, pa.game_stage
            ORDER BY pa.earliest_route ASC, pa.encounter_level DESC NULLS LAST
        ) AS loc_rank
    FROM {{ ref('int_pokemon_availability') }} pa
    LEFT JOIN {{ ref('stg_map_location_groups') }} mlg
        ON mlg.game_route_map = pa.map
    LEFT JOIN {{ ref('stg_map_locations') }} ml
        ON ml.map = mlg.map_location
    WHERE pa.availability_type = 'Catchable'
        AND pa.encounter_level IS NOT NULL
),

best_catch AS (
    SELECT * FROM catch_locations WHERE loc_rank = 1
),

-- Pokemon types
pkmn_types AS (
    SELECT pokemon, type1, type2
    FROM {{ ref('stg_pkmn_stats') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['tt.run_name', 'tt.game_stage', 'tt.team_type', 'tt.pokemon']) }} AS surrogate_key,
    tt.run_name,
    tt.game_stage,
    tt.rival_type,
    tt.keep_pikachu,
    tt.no_legends,
    tt.variant_description,
    tt.pokemon,
    pt.type1,
    pt.type2,
    tt.team_type,
    tt.slot_order,
    tt.pokemon_score,
    tt.performance_tier,
    tt.assigned_tm_move,
    tt.tms_allocated,
    tt.role_on_team,
    tt.team_performance_score,
    tt.team_quality,
    -- EXP fields: use min_exp source for min_exp team, stage_pokemon_costs for others
    CASE
        WHEN tt.team_type = 'min_exp' THEN med.exp_needed
        ELSE eds.fresh_exp_cost
    END AS exp_needed,
    CASE
        WHEN tt.team_type = 'min_exp' THEN med.exp_earned
        ELSE NULL
    END AS exp_earned,
    CASE
        WHEN tt.team_type = 'min_exp' THEN med.exp_deficit
        ELSE NULL
    END AS exp_deficit,
    CASE
        WHEN tt.team_type = 'min_exp' THEN med.exp_status
        ELSE NULL
    END AS exp_status,
    COALESCE(
        CASE WHEN tt.team_type = 'min_exp' THEN med.is_traded ELSE NULL END,
        eds.is_traded,
        0
    ) AS is_traded,
    CASE
        WHEN tt.team_type = 'min_exp' THEN med.coverage_pct
        ELSE NULL
    END AS coverage_pct,
    tt.evolution_note,
    bc.catch_display_name,
    bc.catch_level,
    bc.catch_x,
    bc.catch_y
FROM all_teams tt
LEFT JOIN pkmn_types pt
    ON pt.pokemon = tt.pokemon
LEFT JOIN exp_data_stage eds
    ON eds.pokemon = tt.pokemon
    AND eds.game_stage = tt.game_stage
LEFT JOIN min_exp_data med
    ON med.run_name = tt.run_name
    AND med.game_stage = tt.game_stage
    AND med.pokemon = tt.pokemon
    AND tt.team_type = 'min_exp'
LEFT JOIN best_catch bc
    ON bc.pokemon = tt.pokemon
    AND bc.game_stage = tt.game_stage
ORDER BY tt.run_name, tt.game_stage, tt.team_type, tt.slot_order
