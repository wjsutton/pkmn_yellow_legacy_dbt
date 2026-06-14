-- catch_team_verify (MCP tool) — example invocation.
-- Query logic lives in the catch_team_verify() macro (reusable + parameterised).
-- OUTPUT: one summary row (team_quality, coverage) + one row per swappable slot with
--         the best replacement and the quality it would add.

{{ catch_team_verify(
    team=['Pikachu'],
    badge='Badge_1',
    keep_pikachu='KeepPikachu',
    rival='Flareon',
    legendary='NoLedges'
) }}
