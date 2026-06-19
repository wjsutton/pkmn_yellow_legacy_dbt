# CLAUDE.md

## Project Objective
Find the best 6-pokemon team for every gym leader and all preceding trainers in Pokemon Yellow Legacy (ROM hack). Teams reset at each gym leader -- after defeating Brock, the entire team can change for the Misty segment.

Runs support parameters:
- **Keep Pikachu**: yes/no
- **Use Legendary Pokemon**: yes/no
- **Rival Type**: Jolteon, Vaporeon, or Flareon (each is a separate run)

## Tasks
- Use the dbt mcp server to verify the following success criteria
- For any failures, modify the existing models in the dbt project use the dbt mcp server to support you
- Iterate untill the success criteria is met

## Success Criteria
1. Nidoking should be a potential teammate at Misty's gym (Badge_2)
2. Lt Surge (Badge_3) should have the fewest positive matchups for the player
3. The Rival should always have one of: Eevee, Jolteon, Vaporeon, or Flareon
4. All dbt models should produce rows
5. Staging layer tests: only unique and not_null on primary keys
6. Each team has a maximum of 6 pokemon; single-use TMs can only be assigned once per team (verified by dbt test)
7. The intermediate layer should have no tests
8. Only 5 folders in models/ (staging, intermediate, marts, dashboard, semantic) with no files outside of folders
9. Fewer files in the final layer (marts) than the intermediate layer

## Tools & Environment
- **Database**: DuckDB
- **Framework**: dbt (data build tool) with dbt-duckdb adapter
- **Virtual Environment**: `.venv/Scripts/` (Python, dbt, duckdb executables)
- **MCP Server**: dbt MCP server available for column lineage queries
- **Macros**: Gen 1 battle mechanics (calculate_damage_rby, calculate_hp_rby, calculate_stat_rby, calculate_battle_outcome), run variant generation, TM efficiency

## Required Skills
When working on this dbt project, use these skills from the dbt plugin:
- `dbt:using-dbt-for-analytics-engineering` -- for building/modifying models, debugging errors, exploring data, writing tests
- `dbt:adding-dbt-unit-test` -- when adding unit tests for dbt models
- `dbt:fetching-dbt-docs` -- when looking up dbt features or syntax

## Key Commands
- `.venv/Scripts/python data/create_database.py` -- recreate the DuckDB database
- `.venv/Scripts/python scripts/extract_map_tiles.py` -- regenerate nav_map_tiles/tileset/metadata seeds from the ROM disassembly
- `.venv/Scripts/python scripts/extract_map_warps.py` -- regenerate nav_map_warps seed (warp_events + edge connections) from the ROM disassembly
- `.venv/Scripts/dbt seed` -- load seed CSV data
- `.venv/Scripts/dbt run` -- build all models
- `.venv/Scripts/dbt test` -- run data quality tests
- `.venv/Scripts/dbt run --select <model_name>` -- run a specific model
- `.venv/Scripts/dbt compile` -- compile SQL without running

## Memory Between Iterations

Each iteration is a fresh context. Your only memory is:
- Git hisotry (see previous commits)
- `PROGRESS.md` (learnings from past iterations)
- `CLAUDE.md` (overall object and success criteria)

## Architecture (5 folders)
- **staging/**: Light cleanup of the seed CSV sources. Tests: unique + not_null on primary keys only.
- **intermediate/**: Building-block models (no tests) answering key questions:
  1. What pokemon are available at each game stage? (catchable, trades, evolution by level/stone)
  2. What moveset could each pokemon have? (level-up moves, TMs, HMs at level cap)
  3. What opponent pokemon will we face? (trainer rosters with movesets)
  4. What stats do all pokemon have at any level? (Gen 1 stat formulas)
  Plus EXP source data, encounter lookup, and map/navigation helpers consumed by the marts layer.
- **marts/**: Final analytical layer (fewer files than intermediate). Materialized models:
  - `mart_battle_outcomes` -- who wins in a fight? (battle outcome calculations using macros)
  - `mart_pkmn_level_exp`, `mart_stage_pokemon_costs` -- per-level EXP and per-stage acquisition cost
  - `mart_team_performance`, `mart_recommended_teams`, `mart_min_exp_squads` -- team selection / optimisation
  Tests: max 6 per team, single-use TM uniqueness.
- **dashboard/**: Tableau-ready datasets (3 models, currently `+enabled: false` in dbt_project.yml). Tests: unique + not_null on surrogate keys, accepted values.
- **semantic/**: Semantic layer (no materialized models). The `_catch_semantic.yml` view defines the catch domain -- entities (`pokemon`, `game_stage`, `trainer`) and the relationships between battle_outcomes, stage_pokemon_costs, pokemon_availability, and encounter_lookup -- that power the `catch_*` analytics / MCP tools. (Additional semantic models / metrics live alongside the layers they describe in `intermediate/_semantic.yml`, `marts/_semantic.yml`, and `dashboard/_semantic.yml`.)

## Implementation Plan
See PROGRESS.md for the full restructuring plan and progress.
