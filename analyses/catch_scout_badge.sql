-- catch_scout_badge (MCP tool) — example invocation.
-- Query logic lives in the catch_scout_badge() macro (reusable + parameterised).
-- OUTPUT: one row per opponent on the way to this badge, hardest first — how few
--         counters it has, the best counters, and whether your team handles it.

{{ catch_scout_badge(
    badge='Badge_1',
    keep_pikachu='KeepPikachu',
    rival='Flareon',
    legendary='NoLedges',
    team=['Pikachu']
) }}
