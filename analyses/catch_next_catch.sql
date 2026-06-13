-- next_catch  (MCP tool)
-- INPUT  : team[], badge, keep_pikachu, rival, legendary
-- OUTPUT : every catchable candidate ranked by quality-gain-per-EXP (efficiency),
--          i.e. the best NEXT addition to the current team. Top row = the answer.
--
-- Metric: win_value = max(battle_score,0) * (3 if mini-boss else 1).  Opponents are
-- filtered to the run variant. marginal_gain = how much the candidate improves the
-- team's best answer to each opponent, summed (rewards robustness, not just new wins).

{% set team        = ['Pikachu'] %}        -- current party
{% set badge       = 'Badge_1' %}
{% set keep_pikachu= 'KeepPikachu' %}      -- KeepPikachu | NoPikachu
{% set rival       = 'Flareon' %}          -- Jolteon | Flareon | Vaporeon
{% set legendary   = 'NoLedges' %}         -- NoLedges (exclude) | Ledges (allow)

{% set no_legends  = (legendary == 'NoLedges') %}
{% set run_name    = rival ~ '_' ~ keep_pikachu ~ '_' ~ legendary %}
{% set team_sql    = "'" ~ team | join("','") ~ "'" %}

WITH variant_all AS (
    {{ generate_run_variants(ref('int_battle_outcomes')) }}
),
variant AS (
    SELECT exclude_rival_patterns AS pats, exclude_trainers AS trs
    FROM variant_all WHERE run_name = '{{ run_name }}' AND game_stage = '{{ badge }}' LIMIT 1
),
matchups AS (
    SELECT bo.player_pokemon, bo.trainer_pkmn_id,
           MAX(bo.battle_score) AS best, MAX(bo.is_mini_boss) AS mb
    FROM {{ ref('int_battle_outcomes') }} bo, variant v
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
      {% if no_legends %}AND v.player_pokemon NOT IN ('Moltres','Articuno','Zapdos','Mewtwo','Mew'){% endif %}
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
LEFT JOIN {{ ref('int_stage_pokemon_costs') }} sc
    ON sc.pokemon = g.player_pokemon AND sc.game_stage = '{{ badge }}'
WHERE sc.fresh_exp_cost IS NOT NULL AND g.marginal_gain > 0
ORDER BY gain_per_1k_exp DESC, marginal_gain DESC
