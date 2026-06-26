-- dash_team_winmatrix: candidate x opponent "win value" matrix -- the marginal-gain engine.
-- One row per (run_name, game_stage, candidate pokemon, opponent), filtered to win_value > 0.
-- Tableau computes, for a user-selected party:
--   team_best(opponent) = MAX(win_value) over team members
--   marginal_gain(cand) = SUM(GREATEST(0, win_value - team_best))   [by-damage rank]
-- Scoring ported from macros/catch_next_catch.sql (win_value = GREATEST(score,0) * mini-boss weight).
-- Grain: one row per (run_name, game_stage, pokemon, trainer_pkmn_id)
{{ config(enabled=true) }}

WITH variants AS (
    {{ generate_run_variants(ref('mart_battle_outcomes')) }}
),

-- Best battle_score + mini-boss flag per (candidate, opponent), opponents filtered per run variant.
matchups AS (
    SELECT
        v.run_name,
        v.rival_type,
        v.keep_pikachu,
        v.no_legends,
        bo.game_stage,
        bo.player_pokemon AS pokemon,
        bo.trainer_pkmn_id,
        bo.trainer,
        bo.trainer_pokemon,
        bo.trainer_pkmn_level,
        MAX(bo.battle_score) AS best,
        MAX(bo.is_mini_boss) AS mb
    FROM {{ ref('mart_battle_outcomes') }} bo
    INNER JOIN variants v
        ON v.game_stage = bo.game_stage
       AND NOT (bo.trainer LIKE v.exclude_rival_patterns[1])
       AND NOT (bo.trainer LIKE v.exclude_rival_patterns[2])
       AND NOT list_contains(v.exclude_trainers, bo.trainer)
    GROUP BY
        v.run_name, v.rival_type, v.keep_pikachu, v.no_legends,
        bo.game_stage, bo.player_pokemon, bo.trainer_pkmn_id,
        bo.trainer, bo.trainer_pokemon, bo.trainer_pkmn_level
),

val AS (
    SELECT
        *,
        GREATEST(best, 0) * CASE WHEN mb = 1 THEN 3 ELSE 1 END AS win_value
    FROM matchups
    -- legendary candidates excluded in no-legends runs (mirrors the roster pool)
    WHERE NOT (no_legends = 1 AND {{ is_legendary('pokemon') }})
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['v.run_name', 'v.game_stage', 'v.pokemon', 'v.trainer_pkmn_id']) }} AS surrogate_key,
    v.run_name,
    v.rival_type,
    v.keep_pikachu,
    v.no_legends,
    v.game_stage,
    v.pokemon,
    v.trainer_pkmn_id,
    v.trainer,
    v.trainer_pokemon,
    {{ pokemon_sprite_url('v.trainer_pokemon') }} AS opponent_sprite_url,
    v.trainer_pkmn_level,
    v.best AS battle_score,
    v.mb AS is_mini_boss,
    CASE WHEN v.mb = 1 THEN 3 ELSE 1 END AS opponent_weight,
    v.win_value,
    -- candidate-level scores (from roster): damage = pokemon_score, ease = score / acquisition exp
    r.pokemon_score,
    r.total_acquisition_exp,
    ROUND(r.pokemon_score / GREATEST(r.total_acquisition_exp, 1) * 1000, 3) AS ease_score
FROM val v
LEFT JOIN {{ ref('dash_team_roster') }} r
    ON r.run_name = v.run_name
    AND r.game_stage = v.game_stage
    AND r.pokemon = v.pokemon
WHERE v.win_value > 0
ORDER BY v.run_name, v.game_stage, v.pokemon, v.win_value DESC
