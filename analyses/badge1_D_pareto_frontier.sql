-- badge1_D_pareto_frontier
-- Option D: the "best few given trade-offs" without picking a coverage threshold.
-- Plot whole-route quality vs EXP, then keep only the NON-DOMINATED candidates:
-- a Pokemon is on the frontier if nothing else is both cheaper (<= EXP) AND
-- stronger (>= quality). The frontier IS your shortlist.
--
-- quality = opt_team_performance.route_score: the model's own DIFFICULTY-weighted
-- whole-route score. Beating a hard fight (Brock) is worth far more than beating
-- an easy one -- which is why Mankey (beats Brock) clearly tops Pikachu here, even
-- though a flat win-count would call them a tie. (Same measure as Option A.)
--
-- Scenario: Badge_1, Keep Pikachu, Jolteon rival.

WITH with_cost AS (
    SELECT
        tp.player_pokemon,
        ROUND(tp.route_score, 2) AS quality,
        c.fresh_exp_cost AS exp_to_cap
    FROM {{ ref('opt_team_performance') }} tp
    LEFT JOIN {{ ref('int_stage_pokemon_costs') }} c
        ON c.pokemon = tp.player_pokemon AND c.game_stage = tp.game_stage
    WHERE tp.game_stage = 'Badge_1'
)

SELECT
    w.player_pokemon,
    w.quality,
    w.exp_to_cap,
    -- on the frontier if no other candidate dominates it (cheaper-or-equal AND
    -- stronger-or-equal, and strictly better on at least one axis)
    NOT EXISTS (
        SELECT 1 FROM with_cost o
        WHERE o.player_pokemon <> w.player_pokemon
          AND o.exp_to_cap <= w.exp_to_cap
          AND o.quality   >= w.quality
          AND (o.exp_to_cap < w.exp_to_cap OR o.quality > w.quality)
    ) AS is_pareto_optimal
FROM with_cost w
ORDER BY is_pareto_optimal DESC, w.quality DESC
