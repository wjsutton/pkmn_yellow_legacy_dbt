-- mart_trainer_counters: Trainer difficulty + top 5 counters per opponent pokemon,
-- with where/what-level to catch each counter.
-- Promoted from the deleted dash_trainer_counters (issue #14): the dbtPlaysPokemon
-- agent's planner reads this via dbt_catalog.json "trainer_counters", so it must be
-- an ENABLED mart that survives a clean rebuild (the dashboard layer is disabled).
-- Grain: one row per (run_name, game_stage, trainer_pkmn_id, counter_rank)

WITH run_variants AS (
    {{ generate_run_variants(ref('mart_battle_outcomes')) }}
),

-- Best move per (player_pokemon, trainer_pkmn_id)
best_moves AS (
    SELECT
        bo.game_stage,
        bo.player_pkmn_id,
        bo.player_pokemon,
        bo.trainer,
        bo.is_mini_boss,
        bo.trainer_pkmn_id,
        bo.trainer_pokemon,
        bo.trainer_pkmn_level,
        bo.player_pkmn_move,
        bo.player_pkmn_move_origin,
        bo.player_move_single_use_tm,
        bo.player_attempts_to_ko,
        bo.trainer_pkmn_move,
        bo.trainer_attempts_to_ko,
        bo.battle_score,
        bo.player_victory
    FROM {{ ref('mart_battle_outcomes') }} bo
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY bo.player_pkmn_id, bo.trainer_pkmn_id
        ORDER BY bo.battle_score DESC
    ) = 1
),

-- Trainer difficulty (same formula as mart_team_performance)
trainer_difficulty AS (
    SELECT
        game_stage,
        trainer,
        is_mini_boss,
        AVG(battle_score) AS avg_battle_score,
        MIN(battle_score) AS min_battle_score,
        COUNT(CASE WHEN battle_score >= 0.8 THEN 1 END) AS excellent_counters,
        COUNT(CASE WHEN battle_score >= 0.6 THEN 1 END) AS good_counters,
        COUNT(CASE WHEN player_move_single_use_tm = 1 AND battle_score >= 0.6 THEN 1 END) AS tm_dependent_solutions,
        COUNT(CASE WHEN player_move_single_use_tm = 0 AND battle_score >= 0.6 THEN 1 END) AS natural_solutions
    FROM best_moves
    GROUP BY game_stage, trainer, is_mini_boss
),

difficulty_class AS (
    SELECT
        *,
        {{ trainer_difficulty_rating() }} AS difficulty_rating,
        {{ trainer_difficulty_score() }} AS difficulty_score
    FROM trainer_difficulty
),

-- Rank trainers by difficulty per stage
trainer_ranks AS (
    SELECT
        dc.*,
        ROW_NUMBER() OVER (
            PARTITION BY dc.game_stage
            ORDER BY dc.difficulty_score DESC, dc.avg_battle_score ASC
        ) AS difficulty_rank
    FROM difficulty_class dc
),

-- Rank counter pokemon per trainer_pkmn_id, keep top 5
counter_ranks AS (
    SELECT
        bm.game_stage,
        bm.trainer,
        bm.is_mini_boss,
        bm.trainer_pkmn_id,
        bm.trainer_pokemon,
        bm.trainer_pkmn_level,
        bm.player_pokemon AS counter_pokemon,
        bm.battle_score,
        bm.player_pkmn_move AS counter_move,
        bm.player_pkmn_move_origin AS counter_move_origin,
        bm.player_move_single_use_tm AS requires_single_use_tm,
        bm.player_attempts_to_ko AS player_turns_to_ko,
        bm.trainer_pkmn_move AS opponent_move,
        bm.trainer_attempts_to_ko AS opponent_turns_to_ko,
        CASE WHEN {{ is_legendary('bm.player_pokemon') }}
            THEN 1 ELSE 0
        END AS is_legendary,
        ROW_NUMBER() OVER (
            PARTITION BY bm.trainer_pkmn_id
            ORDER BY bm.battle_score DESC
        ) AS counter_rank
    FROM best_moves bm
),

top_counters AS (
    SELECT * FROM counter_ranks WHERE counter_rank <= 5
),

-- Pokemon types
pkmn_types AS (
    SELECT pokemon, type1, type2
    FROM {{ ref('stg_pkmn_stats') }}
),

{{ collapse_evolution_chains('top_counters', 'counter_pokemon', 'game_stage') }}

-- Opponent types
opponent_types AS (
    SELECT pokemon, type1 AS opponent_type1, type2 AS opponent_type2
    FROM {{ ref('stg_pkmn_stats') }}
),

-- Best catch location + level per (pokemon, game_stage)
catch_locations AS (
    SELECT
        pa.pokemon,
        pa.game_stage,
        ml.display_name AS catch_display_name,
        pa.encounter_level AS catch_level,
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

-- Cross-join trainers with run variants, apply filters
variant_trainers AS (
    SELECT
        rv.run_name,
        rv.rival_type,
        rv.keep_pikachu,
        rv.no_legends,
        rv.exclude_rival_patterns,
        rv.exclude_trainers,
        tr.game_stage,
        tr.trainer,
        tr.is_mini_boss,
        tr.difficulty_rank,
        tr.difficulty_rating,
        {{ generate_variant_description('rv.rival_type', 'rv.keep_pikachu', 'rv.no_legends') }} AS variant_description
    FROM trainer_ranks tr
    INNER JOIN run_variants rv
        ON rv.game_stage = tr.game_stage
    WHERE NOT (tr.trainer LIKE rv.exclude_rival_patterns[1])
      AND NOT (tr.trainer LIKE rv.exclude_rival_patterns[2])
      AND NOT list_contains(rv.exclude_trainers, tr.trainer)
)

SELECT
    vt.run_name,
    vt.rival_type,
    vt.variant_description,
    vt.game_stage,
    vt.trainer,
    vt.is_mini_boss,
    vt.difficulty_rank,
    vt.difficulty_rating,
    tc.trainer_pkmn_id,
    tc.trainer_pokemon,
    tc.trainer_pkmn_level,
    tc.counter_pokemon,
    tc.counter_rank,
    tc.battle_score,
    tc.counter_move,
    tc.counter_move_origin,
    tc.requires_single_use_tm,
    tc.player_turns_to_ko,
    tc.opponent_move,
    tc.opponent_turns_to_ko,
    bc.catch_display_name,
    bc.catch_level,
    en.evolution_note AS counter_evolution_note,
    ot.opponent_type1,
    ot.opponent_type2,
    ct.type1 AS counter_type1,
    ct.type2 AS counter_type2
FROM variant_trainers vt
INNER JOIN top_counters_deduped tc
    ON tc.game_stage = vt.game_stage
    AND tc.trainer = vt.trainer
LEFT JOIN best_catch bc
    ON bc.pokemon = tc.counter_pokemon
    AND bc.game_stage = vt.game_stage
LEFT JOIN _evo_notes en
    ON en.pokemon = tc.counter_pokemon
LEFT JOIN opponent_types ot
    ON ot.pokemon = tc.trainer_pokemon
LEFT JOIN pkmn_types ct
    ON ct.pokemon = tc.counter_pokemon
-- Filter counter pokemon by legendary/pikachu rules per variant
WHERE (vt.no_legends = 0 OR tc.is_legendary = 0)
ORDER BY vt.run_name, vt.game_stage, vt.difficulty_rank, tc.trainer_pkmn_id, tc.counter_rank
