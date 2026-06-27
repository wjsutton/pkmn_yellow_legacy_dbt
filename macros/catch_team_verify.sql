{% macro catch_team_verify(team=['Pikachu'], badge='Badge_1', keep_pikachu='KeepPikachu', rival='Flareon', legendary='NoLedges') %}
{#
    catch_team_verify — scorecard for the current team + best per-slot upgrade.

    Built on the catch semantic view tables (models/semantic/_catch_semantic.yml):
        mart_battle_outcomes + mart_stage_pokemon_costs.

    Returns one summary row (team_quality, coverage) + one row per swappable slot
    showing the best replacement and the quality it would add. Local single-slot
    search: for each member M, the best candidate C maximises
    sum_opponents( max(team_best_without_M, win_value(C)) ).

    Args:
        team         current party species
        badge        game stage, e.g. 'Badge_1' .. 'Badge_8' / 'Elite 4'
        keep_pikachu 'KeepPikachu' (Pikachu slot is fixed) | 'NoPikachu'
        rival        'Jolteon' | 'Flareon' | 'Vaporeon'
        legendary    'NoLedges' (exclude legendaries) | 'Ledges' (allow)

    Returns: slot, replacement, team_quality, coverage, quality_gain_if_swapped,
             replacement_exp
#}
{% set no_legends = (legendary == 'NoLedges') %}
{% set keep_pika = (keep_pikachu == 'KeepPikachu') %}
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
      AND NOT (bo.trainer LIKE v.pats[1]) AND NOT (bo.trainer LIKE v.pats[2])
      AND NOT list_contains(v.trs, bo.trainer)
    GROUP BY 1, 2
),
val AS (
    SELECT *, GREATEST(best, 0) * CASE WHEN mb = 1 THEN 3 ELSE 1 END AS win_value FROM matchups
),
opponents AS (SELECT DISTINCT trainer_pkmn_id FROM val),
team_members AS (
    SELECT DISTINCT player_pokemon FROM val WHERE player_pokemon IN ({{ team_sql }})
),
-- FULL grid: every team member x every opponent, 0 where there is no (winnable)
-- matchup row. Without this, missing rows silently drop opponents from a member's
-- swap sum and invert the gain.
team_grid AS (
    SELECT m.player_pokemon, o.trainer_pkmn_id, COALESCE(v.win_value, 0) AS win_value,
           ROW_NUMBER() OVER (PARTITION BY o.trainer_pkmn_id
                              ORDER BY COALESCE(v.win_value, 0) DESC, m.player_pokemon) AS rnk
    FROM team_members m
    CROSS JOIN opponents o
    LEFT JOIN val v ON v.player_pokemon = m.player_pokemon AND v.trainer_pkmn_id = o.trainer_pkmn_id
),
opp_top AS (
    SELECT trainer_pkmn_id,
           MAX(win_value) AS top1,
           COALESCE(MAX(CASE WHEN rnk = 2 THEN win_value END), 0) AS top2
    FROM team_grid GROUP BY 1
),
-- team's best answer per opponent if member M is removed
without_member AS (
    SELECT tg.player_pokemon AS member, ot.trainer_pkmn_id,
           CASE WHEN tg.rnk = 1 THEN ot.top2 ELSE ot.top1 END AS best_without
    FROM team_grid tg JOIN opp_top ot USING (trainer_pkmn_id)
),
summary AS (
    SELECT SUM(top1) AS team_quality,
           (SELECT COUNT(*) FROM opponents) AS total_opponents,
           SUM(CASE WHEN top1 > 0 THEN 1 ELSE 0 END) AS opponents_beaten
    FROM opp_top
),
candidates AS (
    SELECT DISTINCT player_pokemon FROM val
    WHERE player_pokemon NOT IN ({{ team_sql }})
      {% if no_legends %}AND NOT {{ is_legendary('player_pokemon') }}{% endif %}
),
-- quality of the team if we swap member M out for candidate C
swap AS (
    SELECT wm.member, c.player_pokemon AS replacement,
           SUM(GREATEST(wm.best_without, COALESCE(cv.win_value, 0))) AS q_swap
    FROM without_member wm
    CROSS JOIN candidates c
    LEFT JOIN val cv ON cv.trainer_pkmn_id = wm.trainer_pkmn_id AND cv.player_pokemon = c.player_pokemon
    {% if keep_pika %}WHERE wm.member <> 'Pikachu'{% endif %}
    GROUP BY 1, 2
),
best_swap AS (
    SELECT member, replacement, q_swap,
           ROW_NUMBER() OVER (PARTITION BY member ORDER BY q_swap DESC) AS rn
    FROM swap
)
-- Row 0: overall team scorecard
SELECT
    'TEAM' AS slot, NULL AS replacement,
    ROUND((SELECT team_quality FROM summary), 1) AS team_quality,
    (SELECT opponents_beaten || '/' || total_opponents FROM summary) AS coverage,
    NULL::DOUBLE AS quality_gain_if_swapped, NULL::INT AS replacement_exp
UNION ALL
-- Per-slot best upgrade (only slots where a positive-gain swap exists)
SELECT
    bs.member AS slot, bs.replacement,
    ROUND((SELECT team_quality FROM summary), 1) AS team_quality,
    NULL AS coverage,
    ROUND(bs.q_swap - (SELECT team_quality FROM summary), 1) AS quality_gain_if_swapped,
    sc.fresh_exp_cost AS replacement_exp
FROM best_swap bs
LEFT JOIN {{ ref('mart_stage_pokemon_costs') }} sc
    ON sc.pokemon = bs.replacement AND sc.game_stage = '{{ badge }}'
WHERE bs.rn = 1 AND bs.q_swap - (SELECT team_quality FROM summary) > 0.01
ORDER BY quality_gain_if_swapped DESC NULLS FIRST

{% endmacro %}
