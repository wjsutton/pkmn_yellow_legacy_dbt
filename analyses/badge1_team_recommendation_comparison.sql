-- badge1_team_recommendation_comparison
-- Side-by-side of the team strategies for Badge_1, run 'Jolteon_KeepPikachu_Ledges':
--   * recommended -> mart_recommended_teams (maximise win quality, full 6)
--   * min_exp     -> mart_min_exp_squads     (cheapest set that covers everyone)
-- The 'Marginal (Option C)' team is built by iterating badge1_C_marginal_next_catch
-- and is layered on in the plotting step.
--
-- NOTE: the dashboard models (dash_team_builder) are disabled in dbt_project.yml,
-- so this analysis reads the enabled marts models directly.
-- One row per (strategy, slot).

SELECT
    'recommended'        AS strategy,
    rt.team_rank         AS slot_order,
    rt.player_pokemon    AS pokemon,
    rt.performance_tier,
    rt.role_on_team,
    NULL::INT            AS exp_needed,
    NULL::VARCHAR        AS exp_status,
    NULL::FLOAT          AS coverage_pct
FROM {{ ref('mart_recommended_teams') }} rt
WHERE rt.run_name = 'Jolteon_KeepPikachu_Ledges'
  AND rt.game_stage = 'Badge_1'

UNION ALL

SELECT
    'min_exp'            AS strategy,
    me.pick_order        AS slot_order,
    me.pokemon,
    NULL::VARCHAR        AS performance_tier,
    NULL::VARCHAR        AS role_on_team,
    me.exp_needed,
    me.exp_status,
    me.coverage_pct
FROM {{ ref('mart_min_exp_squads') }} me
WHERE me.run_name = 'Jolteon_KeepPikachu_Ledges'
  AND me.game_stage = 'Badge_1'

ORDER BY strategy, slot_order
