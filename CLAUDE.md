# CLAUDE.md

## Project Objective
Find the best 6-pokemon team for every gym leader and all preceding trainers in Pokemon Yellow Legacy (ROM hack). Teams reset at each gym leader -- after defeating Brock, the entire team can change for the Misty segment.

Runs support parameters:
- **Keep Pikachu**: yes/no
- **Use Legendary Pokemon**: yes/no
- **Rival Type**: Jolteon, Vaporeon, or Flareon (each is a separate run)

## Success Criteria
1. Nidoking should be a potential teammate at Misty's gym (Badge_2)
2. Lt Surge (Badge_3) should have the fewest positive matchups for the player
3. The Rival should always have one of: Eevee, Jolteon, Vaporeon, or Flareon
4. All dbt models should produce rows
5. Staging layer tests: only unique and not_null on primary keys
6. Each team has a maximum of 6 pokemon; single-use TMs can only be assigned once per team (verified by dbt test)
7. The intermediate layer should have no tests
8. Only 3 folders in models/ with no files outside of folders
9. Fewer files in the final layer than the intermediate layer

## Tools & Environment
- **Database**: DuckDB
- **Framework**: dbt (data build tool) with dbt-duckdb adapter
- **Virtual Environment**: `env/Scripts/` (Python, dbt, duckdb executables)
- **MCP Server**: dbt MCP server available for column lineage queries
- **Macros**: Gen 1 battle mechanics (calculate_damage_rby, calculate_hp_rby, calculate_stat_rby, calculate_battle_outcome), run variant generation, TM efficiency

## Key Commands
- `env/Scripts/python data/create_database.py` -- recreate the DuckDB database
- `env/Scripts/dbt seed` -- load seed CSV data
- `env/Scripts/dbt run` -- build all models
- `env/Scripts/dbt test` -- run data quality tests
- `env/Scripts/dbt run --select <model_name>` -- run a specific model
- `env/Scripts/dbt compile` -- compile SQL without running

## Memory Between Iterations

Each iteration is a fresh context. Your only memory is:
- Git hisotry (see previous commits)
- `PROGRESS.md` (learnings from past iterations)
- `CLAUDE.md` (overall object and success criteria)

## Architecture (3 folders only)
- **staging/**: Light cleanup of 15 seed CSV sources. Tests: unique + not_null on primary keys only.
- **intermediate/**: 5 models answering key questions (no tests):
  1. What pokemon are available at each game stage? (catchable, trades, evolution by level/stone)
  2. What moveset could each pokemon have? (level-up moves, TMs, HMs at level cap)
  3. What opponent pokemon will we face? (trainer rosters with movesets)
  4. What stats do all pokemon have at any level? (Gen 1 stat formulas)
  5. Who wins in a fight? (battle outcome calculations using macros)
- **optimisation/**: Final team selection (fewer files than intermediate). Tests: max 6 per team, single-use TM uniqueness.

## Implementation Plan
See PROGRESS.md for the full restructuring plan and progress.
