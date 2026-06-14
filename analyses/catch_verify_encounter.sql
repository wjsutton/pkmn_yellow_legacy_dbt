-- catch_verify_encounter (MCP tool) — example invocation.
-- Query logic lives in the catch_verify_encounter() macro (reusable + parameterised).
-- OUTPUT: one row judging whether the just-encountered wild pokemon is worth catching
--         for this team — marginal value, rank among adds, verdict (ACCEPT/CONSIDER/SKIP).

{{ catch_verify_encounter(
    encountered='Goldeen',
    team=['Pikachu'],
    badge='Badge_1',
    keep_pikachu='KeepPikachu',
    rival='Flareon',
    legendary='NoLedges'
) }}
