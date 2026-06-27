{% macro catch_scout_badge(badge='Badge_1', keep_pikachu='KeepPikachu', rival='Flareon', legendary='NoLedges', team=['Pikachu']) %}
{#
    catch_scout_badge — scout the opponents on the way to a badge, hardest first.

    Built on the catch semantic view tables (models/semantic/_catch_semantic.yml):
        mart_battle_outcomes — player vs opponent matchups.

    One row per opponent pokemon you will face: how few counters it has (the "wall"),
    the best counters available, and whether YOUR current team already handles it.
    Opponents are filtered to the run variant; counters by the legendary rule.

    Args:
        badge        game stage, e.g. 'Badge_1' .. 'Badge_8' / 'Elite 4'
        keep_pikachu 'KeepPikachu' | 'NoPikachu'
        rival        'Jolteon' | 'Flareon' | 'Vaporeon'
        legendary    'NoLedges' (exclude legendaries) | 'Ledges' (allow)
        team         current party species (optional; only flags team coverage)

    Returns: trainer, trainer_pokemon, trainer_pkmn_level, is_mini_boss,
             available_counters, threat_level, best_counter, best_counter_score,
             top_counters, your_team_best_score, team_status
#}
{% set no_legends = (legendary == 'NoLedges') %}
{% set run_name = rival ~ '_' ~ keep_pikachu ~ '_' ~ legendary %}
{% set team_sql = "'" ~ team | join("','") ~ "'" %}

WITH variant_all AS (
    {{ generate_run_variants(ref('mart_battle_outcomes')) }}
),
variant AS (
    SELECT exclude_rival_patterns AS pats, exclude_trainers AS trs
    FROM variant_all WHERE run_name = '{{ run_name }}' AND game_stage = '{{ badge }}' LIMIT 1
),
-- best move per (player pokemon, opponent), variant-filtered, legendary-filtered
matchups AS (
    SELECT bo.player_pokemon, bo.trainer, bo.trainer_pokemon, bo.trainer_pkmn_id,
           bo.trainer_pkmn_level, bo.is_mini_boss,
           MAX(bo.battle_score) AS best_score
    FROM {{ ref('mart_battle_outcomes') }} bo, variant v
    WHERE bo.game_stage = '{{ badge }}'
      AND NOT (bo.trainer LIKE v.pats[1]) AND NOT (bo.trainer LIKE v.pats[2])
      AND NOT list_contains(v.trs, bo.trainer)
      {% if no_legends %}AND NOT {{ is_legendary('bo.player_pokemon') }}{% endif %}
    GROUP BY 1, 2, 3, 4, 5, 6
),
counters AS (
    SELECT player_pokemon, trainer_pkmn_id, best_score,
           ROW_NUMBER() OVER (PARTITION BY trainer_pkmn_id ORDER BY best_score DESC) AS rk
    FROM matchups
),
opp AS (
    SELECT DISTINCT trainer, trainer_pokemon, trainer_pkmn_id, trainer_pkmn_level, is_mini_boss
    FROM matchups
),
n_cnt AS (
    SELECT trainer_pkmn_id, COUNT(*) FILTER (WHERE best_score > 0) AS n_counters
    FROM counters GROUP BY 1
),
best1 AS (
    SELECT trainer_pkmn_id, player_pokemon AS best_counter, best_score AS best_counter_score
    FROM counters WHERE rk = 1
),
top3 AS (
    SELECT trainer_pkmn_id,
           string_agg(player_pokemon || '(' || ROUND(best_score, 2) || ')', ', ' ORDER BY rk) AS top_counters
    FROM counters WHERE rk <= 3 AND best_score > 0 GROUP BY 1
),
team_cov AS (
    SELECT trainer_pkmn_id, MAX(best_score) AS team_best_score
    FROM matchups WHERE player_pokemon IN ({{ team_sql }}) GROUP BY 1
)
SELECT
    o.trainer,
    o.trainer_pokemon,
    o.trainer_pkmn_level,
    o.is_mini_boss,
    COALESCE(nc.n_counters, 0)                                   AS available_counters,
    CASE
        WHEN COALESCE(nc.n_counters, 0) = 0 THEN 'IMPOSSIBLE (no counter at cap)'
        WHEN nc.n_counters <= 2              THEN 'WALL (few counters)'
        WHEN nc.n_counters <= 5              THEN 'Tough'
        ELSE 'Manageable'
    END                                                          AS threat_level,
    b.best_counter,
    ROUND(b.best_counter_score, 2)                              AS best_counter_score,
    t.top_counters,
    ROUND(tc.team_best_score, 2)                               AS your_team_best_score,
    CASE WHEN COALESCE(tc.team_best_score, 0) > 0 THEN 'covered' ELSE 'GAP' END AS team_status
FROM opp o
LEFT JOIN n_cnt nc USING (trainer_pkmn_id)
LEFT JOIN best1 b  USING (trainer_pkmn_id)
LEFT JOIN top3  t  USING (trainer_pkmn_id)
LEFT JOIN team_cov tc USING (trainer_pkmn_id)
ORDER BY o.is_mini_boss DESC, available_counters ASC, best_counter_score ASC

{% endmacro %}
