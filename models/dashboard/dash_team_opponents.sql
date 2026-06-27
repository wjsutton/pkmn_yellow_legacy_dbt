-- dash_team_opponents: full opponent set per run + stage (the team-quality denominator).
-- dash_team_winmatrix only keeps win_value > 0, so opponents that nobody beats vanish there;
-- this table lists every opponent (after rival filtering) so Tableau can compute coverage:
--   team_quality = SUM(opponent_weight where the team beats them) / SUM(opponent_weight)
-- Grain: one row per (run_name, game_stage, trainer_pkmn_id)
{{ config(enabled=true) }}

WITH variants AS (
    {{ generate_run_variants(ref('mart_battle_outcomes')) }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['v.run_name', 'bo.game_stage', 'bo.trainer_pkmn_id']) }} AS surrogate_key,
    v.run_name,
    v.rival_type,
    v.keep_pikachu,
    v.no_legends,
    bo.game_stage,
    bo.trainer_pkmn_id,
    MAX(bo.trainer)        AS trainer,
    MAX(bo.trainer_pokemon) AS trainer_pokemon,
    MAX(bo.is_mini_boss)   AS is_mini_boss,
    CASE WHEN MAX(bo.is_mini_boss) = 1 THEN 3 ELSE 1 END AS opponent_weight
FROM {{ ref('mart_battle_outcomes') }} bo
INNER JOIN variants v
    ON v.game_stage = bo.game_stage
   AND NOT (bo.trainer LIKE v.exclude_rival_patterns[1])
   AND NOT (bo.trainer LIKE v.exclude_rival_patterns[2])
   AND NOT list_contains(v.exclude_trainers, bo.trainer)
GROUP BY v.run_name, v.rival_type, v.keep_pikachu, v.no_legends, bo.game_stage, bo.trainer_pkmn_id
ORDER BY v.run_name, bo.game_stage, bo.trainer_pkmn_id
