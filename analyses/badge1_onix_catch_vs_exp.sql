-- badge1_onix_catch_vs_exp
-- Scenario: Badge_1, Keep Pikachu = yes, Rival = Jolteon.
-- Question: of every Pokemon obtainable by Badge 1, how likely is each to beat
--           Brock's Onix, traded off against the EXP needed to train it to the
--           Badge-1 level cap (Lv.12)?
--
-- Axes for the scatter plot:
--   x = exp_to_cap   (lower is better -- less grinding)
--   y = onix_score   (higher is better -- >0 means it wins the fight)
--
-- Notes on the run parameters:
--   * The Onix matchup itself is independent of rival type, so the Jolteon
--     framing does not change any score here; it is recorded for context.
--   * Keep-Pikachu means Pikachu is a forced party member -- it is included
--     below (and, per the data, it actually loses to Onix).
--   * No legendaries are obtainable by Badge 1, so the no-legends flag is moot.
--
-- Onix is Brock's mini-boss ace: trainer_pkmn_id = 'Brock_Onix_1', Lv.12,
-- Rock/Ground (4x weak to Grass/Water, 2x weak to Fighting). Battle_score is
-- the project's standard outcome metric in [-1, 1]: 1.0 = outspeed + clean OHKO,
-- >0 = win with HP to spare, <=0 = loss (-0.2 is the "trainer moves first" floor).

WITH onix_matchup AS (
    -- Best move each candidate has vs Onix at the Badge-1 level cap
    SELECT
        player_pokemon,
        MAX(battle_score)                                   AS onix_score,
        MAX(CASE WHEN player_victory = 1 THEN 1 ELSE 0 END) AS beats_onix,
        ARG_MAX(player_pkmn_move, battle_score)             AS best_move,
        ARG_MAX(player_pkmn_move_origin, battle_score)      AS best_move_origin
    FROM {{ ref('int_battle_outcomes') }}
    WHERE game_stage = 'Badge_1'
      AND trainer_pkmn_id = 'Brock_Onix_1'
    GROUP BY player_pokemon
),

exp_cost AS (
    -- Cheapest catch option per Pokemon at Badge 1 and the EXP to reach the cap
    SELECT
        pokemon,
        catch_level,
        is_traded,
        fresh_exp_cost AS exp_to_cap
    FROM {{ ref('int_stage_pokemon_costs') }}
    WHERE game_stage = 'Badge_1'
)

SELECT
    o.player_pokemon,
    ROUND(o.onix_score, 3)   AS onix_score,      -- y-axis: likelihood to beat Onix
    o.beats_onix,                                -- 1 = wins, 0 = loses
    c.exp_to_cap,                                -- x-axis: grind cost to Lv.12
    c.catch_level,
    c.is_traded,
    o.best_move,
    o.best_move_origin,
    -- Simple blended priority for ranking the *winners*:
    -- reward win quality, penalise EXP cost (per 1000 EXP).
    ROUND(o.onix_score - (c.exp_to_cap / 1000.0) * 0.15, 3) AS catch_priority
FROM onix_matchup o
LEFT JOIN exp_cost c
    ON c.pokemon = o.player_pokemon
ORDER BY o.beats_onix DESC, o.onix_score DESC, c.exp_to_cap ASC
