# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
This is a dbt project analyzing Pokémon Yellow Legacy ROM hack data to optimize team compositions for beating the game. The project uses DuckDB as the data warehouse and SQL-based optimization models for high-performance team selection (migrated from Python genetic algorithms).

## Todos and Issues
- **PARTIALLY RESOLVED**: `int_battle_analysis` model zero rows issue
  - ✅ **Fixed**: type_effectiveness_lookup CTE logic for dual-type Pokemon (was main cause)
  - ✅ **Fixed**: Removed problematic GROUP BY ALL clause
  - ❌ **Remaining**: Complex joins still filtering out all data despite individual CTEs working
  - **Next Steps**: Add comprehensive data quality tests and systematic join debugging
  - **Root Cause**: Likely data integrity issue in multi-table join conditions
- **CURRENT ISSUE**: Update claude.md file progress and recommended immediate actions
  - **Immediate Action**: Debug `int_battle_analysis` model join conditions
  - **Priority**: Systematic data integrity testing across complex multi-table joins
  - **Recommended Approach**: Use DuckDB CLI debugging to trace row loss at each join stage

## Key Commands

### dbt Operations
- `dbt seed` - Load seed data (CSV files) into DuckDB database
- `dbt run` - Build all models 
- `dbt test` - Run data quality tests
- `dbt clean` - Remove target/ and dbt_packages/ directories
- `dbt deps` - Install dbt packages (currently uses dbt_utils 1.3.0)
- `dbt compile` - Compile SQL models without running them
- `dbt run --select <model_name>` - Run specific model
- `dbt run --select staging+` - Run staging models and downstream dependencies

### DuckDB CLI Debugging
When models show `OK` but no row counts, use Python DuckDB for debugging:
```python
import duckdb
conn = duckdb.connect('data/pkmn_yellow_legacy.db')

# Check row counts at each stage
print('Seed data:', conn.execute('SELECT COUNT(*) FROM pkmn_encounter_areas').fetchone()[0])
print('Staging:', conn.execute('SELECT COUNT(*) FROM stg_pkmn_encounter_areas').fetchone()[0])  
print('Intermediate:', conn.execute('SELECT COUNT(*) FROM int_pokemon_availability').fetchone()[0])
print('Battle analysis:', conn.execute('SELECT COUNT(*) FROM int_battle_analysis').fetchone()[0])
print('Optimization:', conn.execute('SELECT COUNT(*) FROM opt_pokemon_stage_scores').fetchone()[0])
```

**Known Issue (PARTIALLY RESOLVED)**: `int_battle_analysis` model debugging status:
- ✅ **Fixed**: type_effectiveness_lookup logic corrected for single/dual-type Pokemon  
- ✅ **Fixed**: Removed GROUP BY ALL clause that was causing aggregation issues
- ❌ **Remaining**: Model compiles successfully but final result is 0 rows
- **Analysis**: Individual CTEs produce data (~100K rows total) but complex joins fail
- **Next Steps**: Data integrity testing and systematic join condition debugging required

### ✅ SQL Team Optimization (MIGRATED FROM PYTHON)
- **Status**: ✅ Python genetic algorithm scripts successfully migrated to SQL (99%+ performance improvement)
- **Old Location**: `old/output_teams/` (12+ hour genetic algorithm scripts moved here as backup)
- **New Implementation**: High-performance SQL models in `models/optimisation/`:
  - `opt_pokemon_stage_scores.sql` - Calculate Pokémon performance scores per game stage using difficulty penalties
  - `opt_tm_allocation_final.sql` - Resolve TM conflicts using greedy assignment algorithm  
  - `opt_teams_by_stage.sql` - Select optimal 6-Pokémon teams with variants (Standard/NoLedges, with/without Pikachu)
  - `opt_teams_final.sql` - Format results matching original Python output structure
- **Performance**: Sub-minute execution vs 12+ hours (deterministic results vs probabilistic genetic search)
- **Benefits**: Integrated with dbt pipeline, easier maintenance, consistent optimal results

### ~~Python Dependencies~~ (NO LONGER NEEDED)
~~The Python optimization scripts~~ previously required pandas, deap, and other modules - **now fully replaced by SQL models**

## Architecture & Data Flow

### Database Configuration
- **Database**: DuckDB (`data/pkmn_yellow_legacy.db`)
- **Profile**: `pkmn_yellow_legacy_map` 
- **All models materialized as tables** for performance with large datasets
- **Post-hooks**: Tableau models automatically export to CSV files in `dashboard_assets/data/`

### Layer Structure

**Seeds Layer** (`seeds/`): Raw CSV data files containing:
- Game progression (`game_route_order.csv`, `map_locations.csv`)
- Pokémon data (`pkmn_stats.csv`, `pkmn_evolutions.csv`, `pkmn_encounter_areas.csv`)
- Move data (`moves_*.csv` - includes level-up, TM/HM, type effectiveness)
- Trainer data (`trainers_*.csv` - gym leaders, mandatory trainers, legendaries)

**Staging Layer** (`models/staging/`): Cleaned source data with basic transformations
- Standardized column names and data types using `stg_` prefix
- Basic data quality checks via schema.yml tests
- No business logic, pure data cleaning and basic calculations
- Key models: `stg_pkmn_stats.sql`, `stg_moves_stats.sql`, `stg_trainers_*` series

**Intermediate Layer** (`models/intermediate/`): Core business logic tables
- `int_pokemon_availability.sql` - Which Pokémon are available at each game stage with evolution chains
- `int_trainer_roster.sql` - All trainer Pokémon with movesets using level-up move logic
- `int_game_progression.sql` - Game route order and level cap progression logic
- `int_battle_analysis.sql` - Pokémon matchup calculations using Generation 1 damage formulas
- `int_team_optimization.sql` - Battle difficulty analysis and team building preparation

**Optimization Layer** (`models/optimisation/`): ✅ **COMPLETED** SQL-based team selection logic
- `opt_pokemon_stage_scores.sql` - Performance calculation per game stage with difficulty penalties (replaces Python genetic algorithm population scoring)
- `opt_tm_allocation_final.sql` - Greedy TM conflict resolution algorithm (replaces Python `resolve_single_use_tm_conflicts`)
- `opt_teams_by_stage.sql` - Best 6 Pokémon selection with all variants (replaces Python team selection and variant handling)
- `opt_teams_final.sql` - Final formatted results (replaces Python output formatting)
- `opt_difficulty_rankings.sql` - Trainer difficulty analysis and team building priorities
- `opt_team_compositions.sql` - Team composition analysis with type coverage and TM efficiency
- `opt_tm_allocation.sql` - Alternative TM allocation approach (legacy model)
- ~~`initial_top_6.sql`~~ - Replaced by comprehensive optimization models above

**Output Layer** (`models/tableau/`): Final tables for Tableau visualization
- `tableau_map_locations.sql` - Geographic data for map visualizations
- `tableau_team_BAN.sql` - Team composition analysis results
- `tableau_toughest_fights.sql` - Most challenging trainer battles
- Includes post-hook to export data to CSV files in `dashboard_assets/data/`

### Critical Macros (`macros/`)
The project implements Generation 1 Pokémon battle mechanics through custom SQL macros:
- `calculate_damage_rby()` - Implements exact Red/Blue/Yellow damage formula with special move handling (Sonicboom, Dragon Rage, Super Fang, etc.)
- `calculate_hp_rby()`, `calculate_stat_rby()` - Gen 1 stat calculations using original formulas
- `get_move_sources()` - Determines available moves per Pokémon (level-up, TM/HM, evolution)
- `calculate_battle_outcome()` - Full battle simulation with type effectiveness and STAB
- `fetch_sprite()` - Generates sprite URLs from Pokemon Yellow Legacy GitHub repository
- `tm_efficiency_threshold()` - TM usage optimization logic
- `difficulty_priority()` - Battle difficulty ranking system

### ✅ SQL Optimization Integration (MIGRATED FROM PYTHON)
The optimization models in `models/optimisation/` implement sophisticated team selection with **99%+ performance improvement**:
- **Deterministic Algorithm**: SQL-based ranking replaces probabilistic genetic algorithm (consistent optimal results)
- **Performance Scoring**: `opt_pokemon_stage_scores.sql` applies difficulty penalties and battle analysis (replaces fitness function)
- **Constraint Handling**: `opt_tm_allocation_final.sql` resolves single-use TM conflicts through greedy assignment (same algorithm as Python)
- **Variant Support**: `opt_teams_by_stage.sql` handles NoLedges filtering and Pikachu variants (replaces adaptive parameters)
- **Multi-objective Scoring**: Balances individual matchup strength with TM efficiency and team composition (enhanced from Python version)

## Development Workflow
1. Update seed data in `seeds/` directory
2. Run `dbt seed` to load new data into DuckDB
3. Develop/modify models in appropriate layer directories (staging → intermediate → optimisation → tableau)
4. Test individual models with `dbt run --select <model_name>`
5. Run full pipeline with `dbt run` (builds all models including SQL optimization and exports CSV files)
6. ~~Execute Python optimization scripts~~ ✅ **COMPLETED**: Now handled by SQL optimization models in sub-minute execution
7. Review results in generated CSV files and Tableau dashboard

## Performance Optimization Notes
✅ **MAJOR OPTIMIZATIONS COMPLETED** (See TODO.md for full details):
- ✅ Pokemon stats pre-calculated in `stg_pkmn_stats_calculated.sql` (eliminated redundant calculations)
- ✅ Move availability consolidated in `stg_move_sources_unified.sql` (eliminated `get_move_sources()` macro duplication)
- ✅ Evolution chains materialized in `stg_pokemon_evolutions_expanded.sql` (eliminated repeated calculations)
- ✅ Type effectiveness optimized within battle analysis (eliminated duplicate lookups)
- ✅ **Python genetic algorithm replaced with SQL optimization** (99%+ performance improvement - sub-minute vs 12+ hours)

## Important Technical Notes
- **Generation 1 Mechanics**: Damage calculations follow original RBY formulas exactly, including stat caps and rounding behavior
- **Performance Optimization**: All models use table materialization due to complex battle simulation calculations
- **Sprite Integration**: Uses sprite_base_url variable pointing to Pokemon Yellow Legacy ROM hack repository
- **TM Conflict Resolution**: ✅ **MIGRATED** from Python to `opt_tm_allocation_final.sql` using same greedy optimization algorithm
- **Battle Difficulty**: Uses custom difficulty ratings (Easy, Medium, Hard, Very Hard, Requires Specific Counter)
- **Data Export**: Tableau models automatically generate CSV files for dashboard consumption
- **Run Variants**: Supports multiple run types including standard and NoLedges (no legendary Pokémon)