-- opt_min_exp_squads: Minimum-EXP teams via cheapest-counter assignment.
-- For each opponent, assigns it to the cheapest pokemon that can beat it.
-- Then ranks pokemon by assigned coverage / EXP cost to select top 6.
-- Pikachu is forced into slot 1 for KeepPikachu variants.
-- Also computes EXP earned from trainer battles to identify grinding gaps.

WITH run_variants AS (
    {{ generate_run_variants(ref('int_stage_pokemon_costs')) }}
),

-- Deduplicated victories: one row per (game_stage, pokemon, opponent)
base_victories AS (
    SELECT DISTINCT
        bo.game_stage,
        bo.player_pokemon as pokemon,
        spc.fresh_exp_cost as exp_cost,
        bo.trainer_pkmn_id,
        bo.trainer,
        CASE WHEN bo.player_pokemon IN ('Moltres', 'Articuno', 'Zapdos', 'Mewtwo', 'Mew')
            THEN 1 ELSE 0
        END as is_legendary
    FROM {{ ref('int_battle_outcomes') }} bo
    INNER JOIN {{ ref('int_stage_pokemon_costs') }} spc
        ON spc.pokemon = bo.player_pokemon AND spc.game_stage = bo.game_stage
    WHERE bo.player_victory = 1
),

{{ collapse_evolution_chains('base_victories', 'pokemon', 'game_stage') }}

-- Expand to run variants with filtering
stage_coverage AS (
    SELECT
        bv.game_stage,
        rv.run_name,
        rv.keep_pikachu,
        bv.pokemon,
        bv.exp_cost,
        bv.trainer_pkmn_id
    FROM base_victories_deduped bv
    INNER JOIN run_variants rv ON rv.game_stage = bv.game_stage
    WHERE (rv.no_legends = 0 OR bv.is_legendary = 0)
    AND NOT (bv.trainer LIKE rv.exclude_rival_patterns[1])
    AND NOT (bv.trainer LIKE rv.exclude_rival_patterns[2])
    AND NOT list_contains(rv.exclude_trainers, bv.trainer)
),

-- Total opponents per stage/variant (including unbeatable ones)
stage_totals AS (
    SELECT
        rv.run_name,
        op.game_stage,
        COUNT(DISTINCT op.pkmn_id) as total_opponents
    FROM {{ ref('int_opponent_pokemon') }} op
    INNER JOIN run_variants rv ON rv.game_stage = op.game_stage
    WHERE NOT (op.trainer LIKE rv.exclude_rival_patterns[1])
    AND NOT (op.trainer LIKE rv.exclude_rival_patterns[2])
    AND NOT list_contains(rv.exclude_trainers, op.trainer)
    GROUP BY rv.run_name, op.game_stage
),

-- Assign each opponent to its cheapest counter (handles overlap naturally)
opponent_best_counter AS (
    SELECT
        game_stage,
        run_name,
        trainer_pkmn_id,
        pokemon,
        exp_cost,
        ROW_NUMBER() OVER (
            PARTITION BY game_stage, run_name, trainer_pkmn_id
            ORDER BY exp_cost ASC, pokemon ASC
        ) as counter_rank
    FROM stage_coverage
),

-- Count assigned opponents per pokemon (each opponent counted once)
pokemon_assigned AS (
    SELECT
        game_stage,
        run_name,
        pokemon,
        exp_cost,
        COUNT(*) as assigned_opponents
    FROM opponent_best_counter
    WHERE counter_rank = 1
    GROUP BY game_stage, run_name, pokemon, exp_cost
),

-- Also compute total coverage (not just assigned)
pokemon_total_coverage AS (
    SELECT
        game_stage,
        run_name,
        pokemon,
        exp_cost,
        COUNT(DISTINCT trainer_pkmn_id) as total_opponents_beaten
    FROM stage_coverage
    GROUP BY game_stage, run_name, pokemon, exp_cost
),

-- Merge assigned + total coverage and rank
pokemon_ranked AS (
    SELECT
        pa.game_stage,
        pa.run_name,
        pa.pokemon,
        pa.exp_cost,
        pa.assigned_opponents,
        ptc.total_opponents_beaten,
        sc_rv.keep_pikachu,
        ROW_NUMBER() OVER (
            PARTITION BY pa.game_stage, pa.run_name
            ORDER BY
                -- KeepPikachu: force Pikachu to slot 1
                CASE WHEN sc_rv.keep_pikachu = 1 AND pa.pokemon = 'Pikachu' THEN 0 ELSE 1 END,
                -- Then by assigned coverage efficiency
                pa.assigned_opponents::FLOAT / GREATEST(1, pa.exp_cost) DESC,
                pa.assigned_opponents DESC,
                pa.exp_cost ASC
        ) as pick_order
    FROM pokemon_assigned pa
    INNER JOIN pokemon_total_coverage ptc
        ON ptc.game_stage = pa.game_stage
        AND ptc.run_name = pa.run_name
        AND ptc.pokemon = pa.pokemon
    INNER JOIN (
        SELECT DISTINCT game_stage, run_name, keep_pikachu FROM run_variants
    ) sc_rv ON sc_rv.game_stage = pa.game_stage AND sc_rv.run_name = pa.run_name
),

-- Select top 6 per team
final_picks AS (
    SELECT * FROM pokemon_ranked WHERE pick_order <= 6
),

-- Compute actual team coverage (how many opponents the full team of 6 covers)
actual_coverage AS (
    SELECT
        fp.game_stage,
        fp.run_name,
        COUNT(DISTINCT sc.trainer_pkmn_id) as opponents_covered
    FROM final_picks fp
    INNER JOIN stage_coverage sc
        ON sc.game_stage = fp.game_stage
        AND sc.run_name = fp.run_name
        AND sc.pokemon = fp.pokemon
    GROUP BY fp.game_stage, fp.run_name
),

-- === EXP EARNED FROM TRAINER BATTLES ===
-- Reassign opponents to team members only (cheapest team member that beats it)
team_opponent_assignment AS (
    SELECT
        sc.game_stage,
        sc.run_name,
        sc.trainer_pkmn_id,
        sc.pokemon as fighter,
        ROW_NUMBER() OVER (
            PARTITION BY sc.game_stage, sc.run_name, sc.trainer_pkmn_id
            ORDER BY sc.exp_cost ASC, sc.pokemon ASC
        ) as fight_rank
    FROM stage_coverage sc
    INNER JOIN final_picks fp
        ON fp.game_stage = sc.game_stage
        AND fp.run_name = sc.run_name
        AND fp.pokemon = sc.pokemon
),

-- Look up EXP yield for each defeated opponent and sum per team member
-- Traded pokemon gain 1.5x EXP per battle (Gen 1 trade bonus: t = 1.5)
-- exp_earned is in actual EXP terms (what the pokemon's EXP bar receives)
team_exp_earned AS (
    SELECT
        toa.game_stage,
        toa.run_name,
        toa.fighter as pokemon,
        SUM(
            FLOOR(ple.trainer_exp_yield * CASE WHEN spc.is_traded = 1 THEN 1.5 ELSE 1.0 END)
        )::integer as exp_earned,
        COUNT(*) as battles_fought
    FROM team_opponent_assignment toa
    INNER JOIN {{ ref('int_opponent_pokemon') }} op
        ON op.pkmn_id = toa.trainer_pkmn_id
        AND op.game_stage = toa.game_stage
    INNER JOIN {{ ref('int_pkmn_level_exp') }} ple
        ON ple.pokemon = op.pokemon
        AND ple.level = op.pkmn_level
    INNER JOIN {{ ref('int_stage_pokemon_costs') }} spc
        ON spc.pokemon = toa.fighter
        AND spc.game_stage = toa.game_stage
    WHERE toa.fight_rank = 1
    GROUP BY toa.game_stage, toa.run_name, toa.fighter
)

SELECT
    fp.game_stage,
    fp.run_name,
    rv.rival_type,
    rv.keep_pikachu,
    rv.no_legends,
    fp.pokemon,
    fp.pick_order,
    spc.is_traded,
    -- EXP needed in actual terms (undo the trade discount from fresh_exp_cost)
    CASE WHEN spc.is_traded = 1
        THEN ROUND(fp.exp_cost * 1.5)::integer
        ELSE fp.exp_cost
    END as exp_needed,
    fp.assigned_opponents,
    fp.total_opponents_beaten,
    SUM(fp.exp_cost) OVER (PARTITION BY fp.game_stage, fp.run_name) as total_team_exp,
    ac.opponents_covered,
    st.total_opponents,
    ROUND(ac.opponents_covered::FLOAT / GREATEST(st.total_opponents, 1) * 100, 1) as coverage_pct,
    -- EXP budget: actual EXP earned (includes 1.5x trade bonus) vs actual EXP needed
    COALESCE(te.exp_earned, 0) as exp_earned,
    COALESCE(te.battles_fought, 0) as battles_fought,
    (CASE WHEN spc.is_traded = 1 THEN ROUND(fp.exp_cost * 1.5)::integer ELSE fp.exp_cost END)
        - COALESCE(te.exp_earned, 0) as exp_deficit,
    CASE
        WHEN fp.exp_cost = 0 AND spc.is_traded = 1 THEN 'Traded at cap'
        WHEN fp.exp_cost = 0 THEN 'Caught at cap'
        WHEN COALESCE(te.exp_earned, 0) >= (CASE WHEN spc.is_traded = 1 THEN ROUND(fp.exp_cost * 1.5)::integer ELSE fp.exp_cost END)
            THEN 'Self-sustaining'
        WHEN COALESCE(te.exp_earned, 0) >= (CASE WHEN spc.is_traded = 1 THEN ROUND(fp.exp_cost * 1.5)::integer ELSE fp.exp_cost END) * 0.5
            THEN 'Needs minor grinding'
        ELSE 'Needs significant grinding'
    END as exp_status,
    en.evolution_note,
    {{ generate_variant_description('rv.rival_type', 'rv.keep_pikachu', 'rv.no_legends') }} as variant_description
FROM final_picks fp
INNER JOIN run_variants rv
    ON rv.game_stage = fp.game_stage AND rv.run_name = fp.run_name
INNER JOIN actual_coverage ac
    ON ac.game_stage = fp.game_stage AND ac.run_name = fp.run_name
INNER JOIN stage_totals st
    ON st.game_stage = fp.game_stage AND st.run_name = fp.run_name
INNER JOIN {{ ref('int_stage_pokemon_costs') }} spc
    ON spc.pokemon = fp.pokemon AND spc.game_stage = fp.game_stage
LEFT JOIN team_exp_earned te
    ON te.game_stage = fp.game_stage
    AND te.run_name = fp.run_name
    AND te.pokemon = fp.pokemon
LEFT JOIN _evo_notes en
    ON en.pokemon = fp.pokemon
ORDER BY fp.run_name, fp.game_stage, fp.pick_order
