-- recommend_battle_move (catalog key: best_move) — example invocation.
-- The query logic lives in the recommend_battle_move() macro so it is reusable
-- and callable with parameters (e.g. by the agent via `dbt show --inline`, or
-- the fast-path battle_fast.best_move()). This analysis is a runnable example.
--
-- OUTPUT: one row per usable move, best first (will_ko DESC, expected_damage
--         DESC). Top row (recommended = true) is the move to use.
--
-- Example: a level-26 Nidoking facing a level-21 Onix.

{{ recommend_battle_move(
    player_pokemon='Nidoking',
    player_level=26,
    move1='Horn Drill',
    move2='Thrash',
    move3='Double Kick',
    move4='Surf',
    opponent_pokemon='Onix',
    opponent_level=21
) }}
