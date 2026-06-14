-- mart_run_variants: the 12 run-variant definitions per game stage, run_name-keyed.
--
-- Small dimension (~12 variants x distinct game stages). This is the "prefilter data
-- model" for fast AI queries: it materialises the output of the generate_run_variants
-- Jinja macro as a plain table, so the catch_* logic can filter battles with a normal
--     JOIN mart_run_variants v ON v.run_name = ? AND v.game_stage = ?
-- instead of compiling Jinja. That lets the agent run those queries on the persistent
-- DuckDB connection (~25 ms) rather than the `dbt show` subprocess (~4 s).
--
-- Grain: one row per (run_name, game_stage). Columns:
--   run_name, game_stage, rival_type, pikachu_variant, legendary_variant,
--   keep_pikachu, no_legends, exclude_rival_patterns[], exclude_trainers[]

{{ generate_run_variants(ref('mart_battle_outcomes')) }}
