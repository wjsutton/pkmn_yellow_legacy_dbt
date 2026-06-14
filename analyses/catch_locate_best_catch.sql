-- catch_locate_best_catch (MCP tool) — example invocation.
-- Query logic lives in the catch_locate_best_catch() macro (reusable + parameterised).
-- OUTPUT: where to catch the pokemon (or its pre-evolution), ranked best-first by
--         reachable-now encounter probability, with expected casts.

{{ catch_locate_best_catch(
    pokemon='Poliwag',
    badge='Badge_1'
) }}
