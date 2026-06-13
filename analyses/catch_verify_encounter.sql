-- verify_encounter  (MCP tool)
-- INPUT  : encountered, team[], badge, keep_pikachu, rival, legendary
-- OUTPUT : one row judging whether the JUST-ENCOUNTERED wild pokemon is worth
--          catching for THIS team -- its marginal value, its rank among all
--          possible adds, and a verdict (ACCEPT / CONSIDER / SKIP).
--          Implements the satisfice-vs-optimise call: take it, or run and wait?

{% set encountered = 'Goldeen' %}
{% set team        = ['Pikachu'] %}
{% set badge       = 'Badge_1' %}
{% set keep_pikachu= 'KeepPikachu' %}
{% set rival       = 'Flareon' %}
{% set legendary   = 'NoLedges' %}

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
      AND NOT (bo.trainer LIKE v.pats[1]) AND NOT (bo.trainer LIKE v.pats[2])
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
),
scored AS (
    SELECT g.player_pokemon, g.marginal_gain,
           sc.fresh_exp_cost AS exp_to_cap,
           g.marginal_gain / GREATEST(sc.fresh_exp_cost, 1) * 1000 AS gain_per_1k
    FROM gain g
    LEFT JOIN {{ ref('int_stage_pokemon_costs') }} sc
        ON sc.pokemon = g.player_pokemon AND sc.game_stage = '{{ badge }}'
    WHERE sc.fresh_exp_cost IS NOT NULL
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY gain_per_1k DESC) AS rnk,
           COUNT(*) OVER () AS total_adds,
           MAX(gain_per_1k) OVER () AS best_gain_per_1k,
           ARG_MAX(player_pokemon, gain_per_1k) OVER () AS best_alternative
    FROM scored
),
me AS (SELECT * FROM ranked WHERE player_pokemon = '{{ encountered }}')
SELECT
    '{{ encountered }}'                       AS encountered,
    COALESCE(ROUND(me.marginal_gain, 2), 0)   AS marginal_gain,
    me.exp_to_cap,
    COALESCE(ROUND(me.gain_per_1k, 3), 0)     AS gain_per_1k_exp,
    me.rnk                                    AS rank_among_adds,
    me.total_adds,
    me.best_alternative,
    ROUND(me.best_gain_per_1k, 3)             AS best_alt_gain_per_1k,
    CASE
        WHEN me.player_pokemon IS NULL THEN 'SKIP - not a viable/eligible add for this team'
        WHEN me.marginal_gain <= 0.01 THEN 'SKIP - adds no quality the team lacks'
        WHEN me.rnk = 1 THEN 'ACCEPT - best available add'
        WHEN me.gain_per_1k >= 0.7 * me.best_gain_per_1k THEN 'ACCEPT - near-optimal, not worth waiting'
        WHEN me.rnk <= 3 THEN 'CONSIDER - solid, but a better add exists'
        ELSE 'CONSIDER/RUN - a clearly better, comparably cheap add is available'
    END AS verdict
FROM (SELECT 1) x
LEFT JOIN me ON TRUE
