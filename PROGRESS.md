# Progress: Pokemon Yellow Legacy dbt Project Restructuring

## Key Learnings
- DuckDB 1.3.0 removed `CURRENT_TIMESTAMP()` function; use `now()` instead
- DuckDB 1.3.0 uses `::VARCHAR[]` not `::ARRAY(STRING)` for array casting
- DuckDB uses `UNNEST(generate_series(1, 100))` instead of Snowflake's `seq4() + generator()`
- Seeds load to the `main` schema by default in dbt-duckdb; sources.yml must match
- The `defence` spelling is used in staging (British English), keep consistent
