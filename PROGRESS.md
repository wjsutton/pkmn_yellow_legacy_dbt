# Plan: Restructure dbt Project for Pokemon Yellow Legacy

## Goal
Restructure the dbt project to find the best 6-pokemon team for every game stage (gym leader + preceding trainers), resetting the team at each gym leader. Support run parameters: keep Pikachu, use legendaries, rival type (Jolteon/Vaporeon/Flareon as separate runs).

---

## Phase 0: Database Setup & CLAUDE.md

### 0A. Rewrite CLAUDE.md
Rewrite `CLAUDE.md` with the project objective, success criteria, and tools.

### 0B. Recreate Database
- Run `env/Scripts/python data/create_database.py`
- Verify the DB path aligns with profiles.yml
- Run `env/Scripts/dbt seed` to load all 15 seed CSV files

---

## Phase 1: Structural Cleanup

### Target Structure (3 folders only)
```
models/
├── staging/       (15 .sql + _sources.yml + schema.yml)
├── intermediate/  (5 .sql + schema.yml)
└── optimisation/  (2 .sql + schema.yml)
```

### 1A. Delete folders/files
- Delete entire `models/int_no_vibes/` folder (6 old experimental files)
- Delete entire `models/tableau/` folder (2 .sql + schema.yml)
- Delete `macros/generic_tests/trainer_completeness.sql` (references non-existent model)

### 1B. Move files
- Move `models/_sources.yml` -> `models/staging/_sources.yml`

### 1C. Update dbt_project.yml
- Remove `tableau:` section under models config
- Keep staging, intermediate, optimisation materialization configs

---

## Phase 2: Staging Layer (Keep 15 files, fix tests)

### 2A. No SQL changes to staging models
All 15 staging .sql files stay as-is (light cleanup of sources).

### 2B. Rewrite `models/staging/schema.yml`
Strip ALL tests except `unique` + `not_null` on primary keys only:

| Model | PK Column(s) |
|---|---|
| stg_game_route_order | map |
| stg_map_locations | map (not_null only, not unique) |
| stg_moves_from_level_up | id |
| stg_moves_from_tmhm | id |
| stg_moves_phys_spec | id |
| stg_moves_stats | id (remove not_null on type, power, acc, pp) |
| stg_moves_tmhm_locations | tm_or_hm |
| stg_moves_type_effectiveness | id |
| stg_pkmn_encounter_area_order | id |
| stg_pkmn_encounter_areas | id |
| stg_pkmn_evolutions | id |
| stg_pkmn_stats | pokedex (remove not_null on hp, attack, defence, special, speed, total, type1) |
| stg_trainers_gym_leaders | id |
| stg_trainers_legendary | id |
| stg_trainers_mandatory | pkmn_id (remove not_null on trainer) |

---

## Phase 3: Intermediate Layer (Restructure to 5 models)

### 3A. `int_pokemon_availability.sql` -- "What pokemon are available at any point?"
- Modify existing file to absorb `int_game_progression.sql` and `int_pokemon_evolutions_expanded.sql` as CTEs
- Covers: catchable, trades, evolution by level to cap, evolution by stones found/bought
- Must produce Nidoking at Badge_2

### 3B. `int_pokemon_movesets.sql` -- "What moveset could each pokemon have?"
- Rename `int_move_sources_unified.sql` -> `int_pokemon_movesets.sql`
- Covers: level-up moves, TM/HM moves, with route availability

### 3C. `int_opponent_pokemon.sql` -- "What opponents will we face?"
- Rename `int_trainer_roster.sql` -> `int_opponent_pokemon.sql`
- Update ref from `int_move_sources_unified` to `int_pokemon_movesets`
- Covers: all trainer pokemon with movesets per game stage

### 3D. `int_pokemon_stats.sql` -- "What stats at any level?"
- Rename `int_pkmn_stats_calculated.sql` -> `int_pokemon_stats.sql`
- Fix DuckDB syntax: `seq4()` / `generator` -> `UNNEST(generate_series(1, 100))`

### 3E. `int_battle_outcomes.sql` -- "Who wins in a fight?"
- Rename `int_battle_analysis.sql` -> `int_battle_outcomes.sql`, absorb `int_battle_matchups.sql` as CTEs
- Update all refs to new intermediate model names
- Uses macros: `calculate_damage_rby()`, `calculate_battle_outcome()`

### 3F. Delete absorbed/replaced models
- `int_game_progression.sql`, `int_pokemon_evolutions_expanded.sql`, `int_battle_matchups.sql`, `int_team_optimization.sql`, `int_trainer_difficulty.sql`

---

## Phase 4: Optimisation Layer (2 models)

### 4A. `opt_team_performance.sql` -- Merge performance + TM assignments
- Create new file merging `opt_pokemon_performance_by_stage.sql` + `opt_tm_assignments.sql`
- Absorb `int_trainer_difficulty` logic as a CTE

### 4B. `opt_recommended_teams.sql` -- Final team selection
- Update refs to `opt_team_performance`
- Keep run variant logic and top 6 team selection

### 4C. Delete replaced files
- `opt_pokemon_performance_by_stage.sql`, `opt_tm_assignments.sql`

---

## Phase 5: Tests

### 5A. `tests/assert_max_6_per_team.sql`
Fails if any team has more than 6 pokemon.

### 5B. `tests/assert_single_use_tms_unique.sql`
Fails if any single-use TM is assigned to multiple pokemon on same team. Checks against TM data source for single-use identification.

---

## Phase 6: Full Pipeline Validation

### Success Criteria
1. Nidoking available at Badge_2
2. Lt Surge (Badge_3) has fewest positive matchups
3. Rival always has Eevee/Jolteon/Vaporeon/Flareon
4. All models produce rows
5. Staging tests pass (PK-only)
6. Team tests pass (max 6, single-use TMs)
7. Intermediate has no tests
8. Only 3 folders in models/
9. Fewer files in final layer than intermediate (2 < 5)
