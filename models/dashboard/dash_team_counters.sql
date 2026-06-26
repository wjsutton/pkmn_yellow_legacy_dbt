-- dash_team_counters: Trainer difficulty + top 5 counters per opponent pokemon.
-- Drill-down for "this opponent is tough -> who counters it -> where to catch them".
-- Grain: one row per (run_name, game_stage, trainer_pkmn_id, counter_rank)
-- Connect to dash_team_battles on (run_name, game_stage, trainer) and dash_team_catch
-- on (game_stage, counter_pokemon = pokemon) in Tableau.
{{ config(enabled=true) }}

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
        tr.difficulty_score,
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
    {{ dbt_utils.generate_surrogate_key(['vt.run_name', 'tc.trainer_pkmn_id', 'tc.counter_pokemon']) }} AS surrogate_key,
    vt.run_name,
    vt.rival_type,
    vt.keep_pikachu,
    vt.no_legends,
    vt.variant_description,
    vt.game_stage,
    vt.trainer,
    vt.is_mini_boss,
    vt.difficulty_rank,
    vt.difficulty_score,
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
    en.evolution_note AS counter_evolution_note,
    ot.opponent_type1,
    ot.opponent_type2,
    ct.type1 AS counter_type1,
    ct.type2 AS counter_type2,
    -- strategy split: is this counter part of the damage / ease build for this run + stage?
    COALESCE(rost.on_damage_team, 0) AS on_damage_team,
    COALESCE(rost.on_ease_team, 0)   AS on_ease_team
FROM variant_trainers vt
INNER JOIN top_counters_deduped tc
    ON tc.game_stage = vt.game_stage
    AND tc.trainer = vt.trainer
LEFT JOIN _evo_notes en
    ON en.pokemon = tc.counter_pokemon
LEFT JOIN opponent_types ot
    ON ot.pokemon = tc.trainer_pokemon
LEFT JOIN pkmn_types ct
    ON ct.pokemon = tc.counter_pokemon
LEFT JOIN {{ ref('dash_team_roster') }} rost
    ON rost.run_name = vt.run_name
    AND rost.game_stage = vt.game_stage
    AND rost.pokemon = tc.counter_pokemon
-- Filter counter pokemon by legendary/pikachu rules per variant
WHERE (vt.no_legends = 0 OR tc.is_legendary = 0)
ORDER BY vt.run_name, vt.game_stage, vt.difficulty_rank, tc.trainer_pkmn_id, tc.counter_rank
