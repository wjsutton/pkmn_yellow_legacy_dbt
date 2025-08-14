# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
This is a dbt project analyzing Pokémon Yellow Legacy ROM hack data to optimize team compositions for beating the game. The project uses DuckDB as the data warehouse and SQL-based optimization models for high-performance team selection (migrated from Python genetic algorithms).

## Project Status
- ✅ **COMPLETED**: `int_battle_analysis` model zero rows issue fully resolved
- ✅ **COMPLETED**: Python genetic algorithm migration to SQL (99%+ performance improvement)
- ✅ **COMPLETED**: All major performance optimizations implemented
- ✅ **COMPLETED**: Comprehensive data quality testing suite with 236+ tests
- ✅ **COMPLETED**: Team optimization refactored to coverage-based approach (Jan 2025)
- ✅ **COMPLETED**: Gym leader moveset bug fixed in `int_trainer_roster.sql` (Jan 2025)
- **Current State**: Production-ready dbt pipeline with strategic team optimization system

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

### DuckDB CLI Debugging (Optional)
For troubleshooting, you can check row counts across pipeline layers:
```python
import duckdb
conn = duckdb.connect('data/pkmn_yellow_legacy.db')

# Check row counts at each stage
print('Seed data:', conn.execute('SELECT COUNT(*) FROM pkmn_encounter_areas').fetchone()[0])
print('Staging:', conn.execute('SELECT COUNT(*) FROM stg_pkmn_encounter_areas').fetchone()[0])  
print('Intermediate:', conn.execute('SELECT COUNT(*) FROM int_pokemon_availability').fetchone()[0])
print('Battle analysis:', conn.execute('SELECT COUNT(*) FROM int_battle_analysis').fetchone()[0])
print('Optimization:', conn.execute('SELECT COUNT(*) FROM opt_pokemon_performance_by_stage').fetchone()[0])
```

### ✅ SQL Team Optimization (MIGRATED FROM PYTHON)
- **Status**: ✅ Python genetic algorithm scripts successfully migrated to SQL (99%+ performance improvement)
- **Old Location**: `old/output_teams/` (12+ hour genetic algorithm scripts moved here as backup)
- **New Implementation**: High-performance SQL models in `models/optimisation/`:
  - `opt_pokemon_performance_by_stage.sql` - Calculate Pokémon performance scores per game stage using difficulty penalties
  - `opt_tm_assignments.sql` - Resolve TM conflicts using greedy assignment algorithm  
  - `opt_recommended_teams.sql` - Select optimal 6-Pokémon teams with variants (Standard/NoLedges, with/without Pikachu)
  - `opt_team_battle_analysis.sql` - Detailed matchup analysis for recommended teams
- **Performance**: Sub-minute execution vs 12+ hours (deterministic results vs probabilistic genetic search)
- **Benefits**: Integrated with dbt pipeline, easier maintenance, consistent optimal results

### ~~Python Dependencies~~ (NO LONGER NEEDED)
~~The Python optimization scripts~~ previously required pandas, deap, and other modules - **now fully replaced by SQL models**

## Environment Notes
- If you want to call python or duckdb or dbt all the scripts are kept in the virtual environment 'env'  : env/Scripts

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
- `int_trainer_roster.sql` - All trainer Pokémon with movesets (explicit gym leader moves + level-up moves for others)
- `int_game_progression.sql` - Game route order and level cap progression logic
- `int_battle_analysis.sql` - Pokémon matchup calculations using Generation 1 damage formulas
- `int_team_optimization.sql` - Battle difficulty analysis and team building preparation
- `int_trainer_difficulty.sql` - Comprehensive trainer difficulty analysis with priority rankings

**Optimization Layer** (`models/optimisation/`): ✅ **COMPLETED** Strategic team selection logic
- `opt_pokemon_performance_by_stage.sql` - **Team contribution-based scoring** per game stage (Jan 2025 refactor)
- `opt_tm_assignments.sql` - Greedy TM conflict resolution algorithm (replaces Python `resolve_single_use_tm_conflicts`)
- `opt_recommended_teams.sql` - Best 6 Pokémon selection with all variants (replaces Python team selection and variant handling)
- `opt_team_battle_analysis.sql` - Detailed matchup analysis for recommended teams (replaces Python battle simulation)

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

### ✅ Strategic Team Optimization (REFACTORED JAN 2025)
The optimization models in `models/optimisation/` implement sophisticated team selection with **coverage-based approach**:
- **Team Contribution Scoring**: Pokémon ranked by battles where they're the best team option (not individual penalties)
- **Difficulty Weighting**: Gym leaders 3x weight, Very Hard/Extreme battles 2x weight for strategic prioritization
- **Specialist Pokémon Support**: Type specialists (like Poliwag vs Brock) now viable instead of penalized for poor general matchups
- **Battle Coverage Strategy**: Teams built around covering key battles rather than avoiding bad matchups
- **Constraint Handling**: `opt_tm_assignments.sql` resolves single-use TM conflicts through greedy assignment
- **Variant Support**: `opt_recommended_teams.sql` handles NoLedges filtering and Pikachu variants

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
- **TM Conflict Resolution**: ✅ **MIGRATED** from Python to `opt_tm_assignments.sql` using same greedy optimization algorithm
- **Battle Difficulty**: Uses custom difficulty ratings (Easy, Medium, Hard, Very Hard, Extreme) with numerical scoring
- **Gym Leader Movesets**: ✅ **FIXED** `int_trainer_roster.sql` to use explicit moves from seed files (not level-up derivation)
- **Team Strategy**: ✅ **REFACTORED** to coverage-based optimization favoring specialists over generalists
- **Data Export**: Tableau models automatically generate CSV files for dashboard consumption
- **Run Variants**: Supports multiple run types including standard and NoLedges (no legendary Pokémon)

## Debugging Commands
### Data Quality Checks
```python
import duckdb
conn = duckdb.connect('data/pkmn_yellow_legacy.db')

# Check row counts at each stage
print('Seed data:', conn.execute('SELECT COUNT(*) FROM pkmn_encounter_areas').fetchone()[0])
print('Staging:', conn.execute('SELECT COUNT(*) FROM stg_pkmn_encounter_areas').fetchone()[0])  
print('Intermediate:', conn.execute('SELECT COUNT(*) FROM int_pokemon_availability').fetchone()[0])
print('Battle analysis:', conn.execute('SELECT COUNT(*) FROM int_battle_analysis').fetchone()[0])
print('Optimization:', conn.execute('SELECT COUNT(*) FROM opt_pokemon_performance_by_stage').fetchone()[0])
```

### Team Analysis Commands
```python
# Check Pokemon performance at specific stage
result = conn.execute("SELECT player_pokemon, team_selection_score, battles_as_best_option, stage_rank FROM opt_pokemon_performance_by_stage WHERE game_stage = 'Badge_1' ORDER BY team_selection_score DESC LIMIT 10").fetchall()
[print(f'{r[0]}: score={r[1]:.3f}, best_at={r[2]} battles, rank={r[3]}') for r in result]

# Check trainer moveset (useful for debugging gym leader battles)
result = conn.execute("SELECT pkmn_id, pokemon, level, move_1, move_2, move_3, move_4 FROM int_trainer_roster WHERE trainer = 'Erica_4' AND pokemon = 'Victreebel'").fetchall()
[print(f'{r[0]}: {r[1]} L{r[2]} - {r[3]}, {r[4]}, {r[5]}, {r[6]}') for r in result]

# Check battle matchup details
result = conn.execute("SELECT player_pokemon, trainer_pokemon, battle_score, player_pkmn_move, trainer_pkmn_move, player_attempts_to_ko, trainer_attempts_to_ko FROM int_battle_analysis WHERE game_stage = 'Badge_4' AND trainer = 'Erica_4' AND trainer_pokemon = 'Victreebel' AND player_pokemon = 'Onix' ORDER BY battle_score DESC LIMIT 3").fetchall()
[print(f'{r[0]} vs {r[1]}: {r[2]:.3f} using {r[3]} vs {r[4]} (player KOs in {r[5]:.1f}, trainer KOs in {r[6]:.1f})') for r in result]
```