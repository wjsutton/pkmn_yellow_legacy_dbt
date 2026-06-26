-- dash_team_roster: the candidate POOL for the interactive team-builder.
-- One row per obtainable pokemon for a run + game stage, with acquisition attributes and
-- a flag for whether it was on the precomputed damage / ease team (the old roster content).
-- Tableau picks a party from this pool; dash_team_winmatrix + dash_team_opponents drive the
-- marginal "next best add" and team-quality math.
-- Grain: one row per (run_name, game_stage, pokemon)
-- Downstream (battles/moves/catch) filter to on_damage_team=1 OR on_ease_team=1 to keep the
-- "precomputed team" meaning. The full optimal team also lives in dash_team_builder.
{{ config(enabled=true) }}

WITH variants AS (
    {{ generate_run_variants(ref('mart_battle_outcomes')) }}
),

run_stage AS (
    SELECT DISTINCT run_name, rival_type, keep_pikachu, no_legends, game_stage
    FROM variants
),

-- Candidate universe per stage (run-independent): every catchable / obtainable form.
-- Keep ALL forms (Poliwag AND Poliwhirl) -- evolved forms are ordinary later-stage candidates.
pool AS (
    SELECT
        game_stage,
        pokemon,
        MIN(initial_pokemon)   AS initial_pokemon,
        MIN(pokemon_category)  AS pokemon_category,
        MIN(encounter_level)   AS encounter_level
    FROM {{ ref('int_pokemon_availability') }}
    WHERE availability_type IN ('Catchable', 'Team Option')
    GROUP BY game_stage, pokemon
),

stage_costs AS (
    SELECT pokemon, game_stage, fresh_exp_cost, catch_level, is_traded, trade_give_pokemon
    FROM {{ ref('mart_stage_pokemon_costs') }}
),

-- EXP-equivalent wild-catch cost + representative (earliest reachable) catch location.
-- Mirrors the catch_cost CTE in macros/catch_next_catch.sql.
catch_cost AS (
    SELECT
        pa.pokemon    AS candidate,
        pa.game_stage,
        MIN({{ calculate_catch_cost_exp('el.total_probability', 'el.catch_rate', 'el.avg_wild_exp') }}) AS catch_cost_exp,
        ARG_MIN(el.map_name, el.badges_to_reach)        AS catch_map,
        ARG_MIN(el.area, el.badges_to_reach)            AS catch_area,
        ARG_MIN(el.catch_difficulty, el.badges_to_reach) AS catch_difficulty
    FROM {{ ref('int_pokemon_availability') }} pa
    INNER JOIN {{ ref('int_encounter_lookup') }} el
        ON el.pokemon = pa.initial_pokemon
    WHERE pa.availability_type = 'Catchable'
      AND el.badges_to_reach <=
          CASE WHEN pa.game_stage LIKE 'Badge_%'
               THEN CAST(REPLACE(pa.game_stage, 'Badge_', '') AS INT) - 1
               ELSE 8 END
    GROUP BY pa.pokemon, pa.game_stage
),

-- Per-pokemon solo quality score (run-independent, one per game_stage x pokemon)
pkmn_score AS (
    SELECT
        game_stage,
        player_pokemon AS pokemon,
        MAX(team_selection_score) AS pokemon_score,
        MAX(performance_tier)     AS performance_tier
    FROM {{ ref('mart_team_performance') }}
    GROUP BY game_stage, player_pokemon
),

-- Old precomputed team membership (run-variant aware)
damage_team AS (
    SELECT run_name, game_stage, player_pokemon AS pokemon, team_rank
    FROM {{ ref('mart_recommended_teams') }}
),
ease_team AS (
    SELECT run_name, game_stage, pokemon, pick_order
    FROM {{ ref('mart_min_exp_squads') }}
),

-- inject _evo_notes (evolution_note); the _deduped CTE is intentionally unused -- we keep
-- every evolution form as its own candidate.
{{ collapse_evolution_chains('pool', 'pokemon', 'game_stage') }}

candidates AS (
    SELECT
        rs.run_name,
        rs.rival_type,
        rs.keep_pikachu,
        rs.no_legends,
        {{ generate_variant_description('rs.rival_type', 'rs.keep_pikachu', 'rs.no_legends') }} AS variant_description,
        p.game_stage,
        p.pokemon,
        p.initial_pokemon,
        p.pokemon_category,
        p.encounter_level,
        sc.catch_level,
        COALESCE(sc.is_traded, 0) AS is_traded,
        sc.trade_give_pokemon,
        sc.fresh_exp_cost AS exp_to_cap,
        cc.catch_cost_exp,
        sc.fresh_exp_cost + COALESCE(cc.catch_cost_exp, 0) AS total_acquisition_exp,
        cc.catch_map,
        cc.catch_area,
        cc.catch_difficulty,
        en.evolution_note,
        ps.pokemon_score,
        ps.performance_tier,
        CASE WHEN {{ is_legendary('p.pokemon') }} THEN 1 ELSE 0 END AS is_legendary,
        CASE WHEN dt.team_rank IS NOT NULL THEN 1 ELSE 0 END AS on_damage_team,
        dt.team_rank AS damage_rank,
        CASE WHEN et.pick_order IS NOT NULL THEN 1 ELSE 0 END AS on_ease_team,
        et.pick_order AS ease_pick_order
    FROM pool p
    INNER JOIN run_stage rs
        ON rs.game_stage = p.game_stage
    LEFT JOIN stage_costs sc
        ON sc.pokemon = p.pokemon AND sc.game_stage = p.game_stage
    LEFT JOIN catch_cost cc
        ON cc.candidate = p.pokemon AND cc.game_stage = p.game_stage
    LEFT JOIN _evo_notes en
        ON en.pokemon = p.pokemon
    LEFT JOIN pkmn_score ps
        ON ps.game_stage = p.game_stage AND ps.pokemon = p.pokemon
    LEFT JOIN damage_team dt
        ON dt.run_name = rs.run_name AND dt.game_stage = p.game_stage AND dt.pokemon = p.pokemon
    LEFT JOIN ease_team et
        ON et.run_name = rs.run_name AND et.game_stage = p.game_stage AND et.pokemon = p.pokemon
    -- legendary candidates excluded in no-legends runs; pikachu is a slot constraint, not a filter
    WHERE (rs.no_legends = 0 OR NOT {{ is_legendary('p.pokemon') }})
      AND sc.fresh_exp_cost IS NOT NULL
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['run_name', 'game_stage', 'pokemon']) }} AS surrogate_key,
    run_name,
    rival_type,
    keep_pikachu,
    no_legends,
    variant_description,
    game_stage,
    pokemon,
    {{ pokemon_sprite_url('pokemon') }} AS sprite_url,
    initial_pokemon,
    pokemon_category,
    encounter_level,
    catch_level,
    is_traded,
    trade_give_pokemon,
    exp_to_cap,
    catch_cost_exp,
    total_acquisition_exp,
    catch_map,
    catch_area,
    catch_difficulty,
    evolution_note,
    -- damage = raw solo quality; ease = quality per acquisition EXP
    pokemon_score,
    performance_tier,
    ROUND(pokemon_score / GREATEST(total_acquisition_exp, 1) * 1000, 3) AS ease_score,
    is_legendary,
    on_damage_team,
    damage_rank,
    on_ease_team,
    ease_pick_order
FROM candidates
ORDER BY run_name, game_stage, pokemon
