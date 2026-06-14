{% macro catch_next_catch(team=['Pikachu'], badge='Badge_1', keep_pikachu='KeepPikachu', rival='Flareon', legendary='NoLedges') %}
{#
    catch_next_catch — best NEXT addition to the current team.

    Built on the catch semantic view tables (models/semantic/_catch_semantic.yml):
        mart_battle_outcomes   — player vs opponent matchups (win quality)
        mart_stage_pokemon_costs — EXP-to-cap per catchable pokemon

    Returns every catchable candidate ranked by quality-gain-per-EXP; the top row
    is the answer. Opponents are filtered to the run variant via generate_run_variants.

    Args:
        team         list of current party species, e.g. ['Pikachu', 'Nidoking']
        badge        game stage, e.g. 'Badge_1' .. 'Badge_8' / 'Elite 4'
        keep_pikachu 'KeepPikachu' | 'NoPikachu'
        rival        'Jolteon' | 'Flareon' | 'Vaporeon'
        legendary    'NoLedges' (exclude legendaries) | 'Ledges' (allow)

    Returns columns: candidate, marginal_gain, exp_to_cap, gain_per_1k_exp,
                     catch_level, is_traded
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
matchups AS (
    SELECT bo.player_pokemon, bo.trainer_pkmn_id,
           MAX(bo.battle_score) AS best, MAX(bo.is_mini_boss) AS mb
    FROM {{ ref('mart_battle_outcomes') }} bo, variant v
    WHERE bo.game_stage = '{{ badge }}'
      AND NOT (bo.trainer LIKE v.pats[1])
      AND NOT (bo.trainer LIKE v.pats[2])
      AND NOT list_contains(v.trs, bo.trainer)
    GROUP BY 1, 2
),
val AS (
    SELECT *, GREATEST(best, 0) * CASE WHEN mb = 1 THEN 3 ELSE 1 END AS win_value FROM matchups
),
team_best AS (
    SELECT trainer_pkmn_id, MAX(win_value) AS tv
    FROM val WHERE player_pokemon IN ({{ team_sql }}) GROUP BY 1
),
gain AS (
    SELECT v.player_pokemon,
           SUM(GREATEST(0, v.win_value - COALESCE(tb.tv, 0))) AS marginal_gain
    FROM val v LEFT JOIN team_best tb USING (trainer_pkmn_id)
    WHERE v.player_pokemon NOT IN ({{ team_sql }})
      {% if no_legends %}AND NOT {{ is_legendary('v.player_pokemon') }}{% endif %}
    GROUP BY 1
)
SELECT
    g.player_pokemon                                                   AS candidate,
    ROUND(g.marginal_gain, 2)                                          AS marginal_gain,
    sc.fresh_exp_cost                                                  AS exp_to_cap,
    ROUND(g.marginal_gain / GREATEST(sc.fresh_exp_cost, 1) * 1000, 3)  AS gain_per_1k_exp,
    sc.catch_level,
    sc.is_traded
FROM gain g
LEFT JOIN {{ ref('mart_stage_pokemon_costs') }} sc
    ON sc.pokemon = g.player_pokemon AND sc.game_stage = '{{ badge }}'
WHERE sc.fresh_exp_cost IS NOT NULL AND g.marginal_gain > 0
ORDER BY gain_per_1k_exp DESC, marginal_gain DESC

{% endmacro %}
