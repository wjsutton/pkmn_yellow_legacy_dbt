-- badge1_B_coverage_heatmap
-- Option B: a (candidate Pokemon x opponent) matrix of best battle_score, so you
-- can SEE complementarity -- e.g. Poliwag's weak columns on Jigglypuff/Pinsir that
-- Mankey fills. Long format here; pivot to a grid in the plotting layer.
--
-- best_score is the best move's outcome in [-1, 1] (>0 wins). Because Gen-1 has
-- damage rolls / crits / accuracy, a high positive score is a *robust* win whereas
-- a score just above 0 is a coin-flip -- the colour scale should reflect that.
--
-- Scenario: Badge_1, Keep Pikachu, Jolteon rival (all 17 route opponents kept;
-- the Jolteon variant only excludes later %_Flareon/%_Vaporeon rival fights).

SELECT
    bo.player_pokemon,
    bo.trainer,
    bo.trainer_pokemon,
    bo.trainer_pkmn_id,
    bo.trainer_pkmn_level,
    bo.is_mini_boss,
    -- mini-bosses (Brock, rival) matter more: weight them up
    CASE WHEN bo.is_mini_boss = 1 THEN 3 ELSE 1 END AS opponent_weight,
    MAX(bo.battle_score) AS best_score,
    -- quality-weighted "coverage value": a loss contributes 0, a strong win more
    GREATEST(MAX(bo.battle_score), 0) * CASE WHEN bo.is_mini_boss = 1 THEN 3 ELSE 1 END AS win_value
FROM {{ ref('mart_battle_outcomes') }} bo
WHERE bo.game_stage = 'Badge_1'
GROUP BY bo.player_pokemon, bo.trainer, bo.trainer_pokemon,
         bo.trainer_pkmn_id, bo.trainer_pkmn_level, bo.is_mini_boss
ORDER BY bo.player_pokemon, opponent_weight DESC, bo.trainer_pkmn_id
