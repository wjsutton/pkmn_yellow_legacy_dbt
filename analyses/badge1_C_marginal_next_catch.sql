-- badge1_C_marginal_next_catch
-- Option C: "given my CURRENT party, what is the best NEXT catch?"
-- For every candidate, marginal_gain = how much it improves the team's best
-- answer to each opponent, summed (quality-weighted, so it rewards turning a
-- shaky win into a robust one -- important given Gen-1 randomness), NOT just
-- newly-covered opponents.
--
-- This is the greedy step. To build a team: read the top row, add it to
-- current_party below, re-run. Repeat until marginal_gain stops being worth the EXP.
--
-- Scenario: Badge_1, Keep Pikachu, Jolteon rival. Current party starts as Pikachu.

{% set current_party = ['Pikachu'] %}   -- <-- edit this list and re-run to iterate

WITH matchups AS (
    SELECT
        bo.player_pokemon,
        bo.trainer_pkmn_id,
        CASE WHEN bo.is_mini_boss = 1 THEN 3 ELSE 1 END AS opponent_weight,
        GREATEST(MAX(bo.battle_score), 0) * CASE WHEN bo.is_mini_boss = 1 THEN 3 ELSE 1 END AS win_value
    FROM {{ ref('mart_battle_outcomes') }} bo
    WHERE bo.game_stage = 'Badge_1'
    GROUP BY bo.player_pokemon, bo.trainer_pkmn_id, bo.is_mini_boss
),

-- Best quality-weighted value the CURRENT party already achieves per opponent
party_best AS (
    SELECT
        trainer_pkmn_id,
        MAX(win_value) AS party_value
    FROM matchups
    WHERE player_pokemon IN ({{ "'" ~ current_party | join("','") ~ "'" }})
    GROUP BY trainer_pkmn_id
),

-- Marginal improvement each candidate adds on top of the current party
candidate_gain AS (
    SELECT
        m.player_pokemon,
        SUM(GREATEST(0, m.win_value - COALESCE(pb.party_value, 0))) AS marginal_gain
    FROM matchups m
    LEFT JOIN party_best pb ON pb.trainer_pkmn_id = m.trainer_pkmn_id
    WHERE m.player_pokemon NOT IN ({{ "'" ~ current_party | join("','") ~ "'" }})
    GROUP BY m.player_pokemon
)

SELECT
    cg.player_pokemon,
    ROUND(cg.marginal_gain, 2) AS marginal_gain,   -- y-axis
    c.fresh_exp_cost AS exp_to_cap,                 -- x-axis
    ROUND(cg.marginal_gain / GREATEST(c.fresh_exp_cost, 1) * 1000, 3) AS gain_per_1k_exp
FROM candidate_gain cg
LEFT JOIN {{ ref('mart_stage_pokemon_costs') }} c
    ON c.pokemon = cg.player_pokemon AND c.game_stage = 'Badge_1'
ORDER BY cg.marginal_gain DESC, c.fresh_exp_cost ASC
