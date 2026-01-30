# Progress: Pokemon Yellow Legacy dbt Project Restructuring

## Status: COMPLETE

All phases executed successfully. Full pipeline runs with `dbt seed`, `dbt run` (22 models), and `dbt test` (31 tests) all passing.

---

## Completed Changes

### Phase 1: Structural Cleanup
- Deleted `models/int_no_vibes/` (6 experimental models)
- Deleted `models/tableau/` (2 dashboard models + schema.yml)
- Moved `models/_sources.yml` to `models/staging/_sources.yml`
- Removed `tableau:` section from `dbt_project.yml`
- Deleted `macros/generic_tests/trainer_completeness.sql` (referenced non-existent model)

### Phase 2: Staging Layer Tests
- Stripped non-PK tests from `schema.yml`:
  - `stg_moves_stats`: removed not_null on type, power, acc, pp
  - `stg_pkmn_stats`: removed not_null on hp, attack, defence, special, speed, total, type1
  - `stg_trainers_mandatory`: removed not_null on trainer, kept PK as pkmn_id

### Phase 3: Intermediate Layer (10 models -> 5)
- **int_pokemon_availability**: Absorbed `int_game_progression` + `int_pokemon_evolutions_expanded` as CTEs
- **int_pokemon_movesets**: Renamed from `int_move_sources_unified`
- **int_opponent_pokemon**: Renamed from `int_trainer_roster`, updated ref to `int_pokemon_movesets`
- **int_pokemon_stats**: Renamed from `int_pkmn_stats_calculated`, fixed DuckDB syntax (`seq4()/generator()` -> `UNNEST(generate_series())`)
- **int_battle_outcomes**: Renamed from `int_battle_analysis`, absorbed `int_battle_matchups` as CTEs, updated all refs to renamed models
- Deleted: `int_game_progression`, `int_pokemon_evolutions_expanded`, `int_battle_matchups`, `int_team_optimization`, `int_trainer_difficulty`
- Rewrote `schema.yml` with NO tests (descriptions only)

### Phase 4: Optimisation Layer (3 models -> 2)
- **opt_team_performance**: New model merging `opt_pokemon_performance_by_stage` + `opt_tm_assignments`, absorbed `int_trainer_difficulty` logic
- **opt_recommended_teams**: Updated refs to `opt_team_performance`, removed refs to old models
- Deleted: `opt_pokemon_performance_by_stage`, `opt_tm_assignments`

### Phase 5: Tests
- Created `tests/assert_max_6_per_team.sql`
- Created `tests/assert_single_use_tms_unique.sql`

### Bug Fixes During Validation
- Fixed `macros/add_dbt_loaded_at_col.sql`: `CURRENT_TIMESTAMP()` -> `now()` for DuckDB compatibility
- Fixed `macros/generate_run_variants.sql`: `::ARRAY(STRING)` -> `::VARCHAR[]` for DuckDB 1.3.0 compatibility
- Fixed `models/staging/_sources.yml`: schema `dbt_wsutton` -> `main` (seeds load to main)
- Fixed `analyses/all_opponents.sql`: updated ref from `int_battle_analysis` to `int_battle_outcomes`
- Fixed `int_pokemon_stats.sql`: column `defense` -> `defence` (matching staging output)

---

## Success Criteria Validation

| # | Criteria | Status |
|---|---------|--------|
| 1 | Nidoking available at Badge_2 | PASS (via Celadon City stone evolution) |
| 2 | Lt Surge (Badge_3) fewest positive matchups | PASS (0 positive matchups - lowest of all gym leaders) |
| 3 | Rival always has Eevee/Jolteon/Vaporeon/Flareon | PASS (all variants present) |
| 4 | All dbt models produce rows | PASS (22/22 models have rows) |
| 5 | Staging tests: unique + not_null on PKs only | PASS (31 tests, all passing) |
| 6 | Max 6 per team + single-use TM uniqueness | PASS (custom tests pass) |
| 7 | Intermediate layer has no tests | PASS (descriptions only in schema.yml) |
| 8 | Only 3 folders in models/ | PASS (staging, intermediate, optimisation) |
| 9 | Fewer files in final layer than intermediate | PASS (2 < 5) |

---

## Final Architecture
```
models/
├── staging/          (15 .sql + _sources.yml + schema.yml)
├── intermediate/     (5 .sql + schema.yml, NO tests)
└── optimisation/     (2 .sql + schema.yml)
tests/
├── assert_max_6_per_team.sql
└── assert_single_use_tms_unique.sql
```

## Key Learnings
- DuckDB 1.3.0 removed `CURRENT_TIMESTAMP()` function; use `now()` instead
- DuckDB 1.3.0 uses `::VARCHAR[]` not `::ARRAY(STRING)` for array casting
- DuckDB uses `UNNEST(generate_series(1, 100))` instead of Snowflake's `seq4() + generator()`
- Seeds load to the `main` schema by default in dbt-duckdb; sources.yml must match
- The `defence` spelling is used in staging (British English), keep consistent
