-- what_team_to_build
-- "What team should I build?" for a given run variant + badge.
-- Edit the four vars below and re-run. Returns two strategies side by side:
--   * min_exp     -> beat the stage with the LEAST grind (your primary build)
--   * recommended -> the max-quality full 6 (fallback / if you want more margin)
--
-- Current scenario: Badge_1, have Pikachu, Flareon rival, KEEP Pikachu, NO legendaries.

{% set rival_type   = 'Flareon'      %}   -- Jolteon | Flareon | Vaporeon
{% set pikachu_opt  = 'KeepPikachu'  %}   -- KeepPikachu | NoPikachu
{% set legendary    = 'NoLedges'     %}   -- NoLedges (no legendaries) | Ledges (allowed)
{% set badge        = 'Badge_1'      %}
{% set run_name     = rival_type ~ '_' ~ pikachu_opt ~ '_' ~ legendary %}

-- Primary: minimum-EXP team that still covers the whole stage
SELECT
    'min_exp'                AS strategy,
    pick_order               AS slot,
    pokemon,
    exp_needed,
    exp_status,
    coverage_pct,
    NULL::VARCHAR            AS performance_tier,
    evolution_note,
    SUM(exp_needed) OVER ()  AS team_total_exp
FROM {{ ref('opt_min_exp_squads') }}
WHERE run_name = '{{ run_name }}' AND game_stage = '{{ badge }}'

UNION ALL

-- Fallback: max-quality full six
SELECT
    'recommended'            AS strategy,
    team_rank                AS slot,
    player_pokemon           AS pokemon,
    NULL::INT                AS exp_needed,
    NULL::VARCHAR            AS exp_status,
    NULL::FLOAT              AS coverage_pct,
    performance_tier,
    evolution_note,
    NULL::INT                AS team_total_exp
FROM {{ ref('opt_recommended_teams') }}
WHERE run_name = '{{ run_name }}' AND game_stage = '{{ badge }}'

ORDER BY strategy, slot
