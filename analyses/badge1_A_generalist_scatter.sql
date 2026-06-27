-- badge1_A_generalist_scatter
-- Option A: the same scatter as badge1_onix_catch_vs_exp, but the Y-axis is the
-- WHOLE-ROUTE difficulty-weighted score instead of "score vs Onix only".
-- This surfaces all-rounders: Mankey (good vs the whole route) overtakes
-- Poliwag (a Brock specialist).
--
-- Scenario: Badge_1, Keep Pikachu, Jolteon rival.
--   x = exp_to_cap   (mart_stage_pokemon_costs.fresh_exp_cost, lower = less grind)
--   y = route_score  (mart_team_performance.route_score = sum of best battle_score
--                     per opponent, weighted up for mini-bosses; the model's own
--                     whole-route quality measure)

SELECT
    tp.player_pokemon,
    tp.route_score,                 -- y-axis: whole-route quality
    tp.stage_rank,
    tp.performance_tier,
    c.fresh_exp_cost AS exp_to_cap, -- x-axis: grind cost to Lv.12
    c.catch_level,
    c.is_traded
FROM {{ ref('mart_team_performance') }} tp
LEFT JOIN {{ ref('mart_stage_pokemon_costs') }} c
    ON c.pokemon = tp.player_pokemon
   AND c.game_stage = tp.game_stage
WHERE tp.game_stage = 'Badge_1'
ORDER BY tp.route_score DESC
