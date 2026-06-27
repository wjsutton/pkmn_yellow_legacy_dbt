-- catch_next_catch (MCP tool) — example invocation.
-- The query logic now lives in the catch_next_catch() macro so it is reusable and
-- callable with parameters (e.g. by the agent via `dbt show --inline`). This analysis
-- is just a runnable example with the default arguments.
--
-- OUTPUT: every catchable candidate ranked by quality-gain-per-EXP (efficiency),
--         i.e. the best NEXT addition to the current team. Top row = the answer.

{{ catch_next_catch(
    team=['Pikachu'],
    badge='Badge_1',
    keep_pikachu='KeepPikachu',
    rival='Flareon',
    legendary='NoLedges'
) }}
