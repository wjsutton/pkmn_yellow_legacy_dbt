# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview
This is a dbt project analyzing Pokémon Yellow Legacy ROM hack data to optimize team compositions for beating the game. The project uses DuckDB as the data warehouse and includes Python scripts for advanced team optimization using genetic algorithms.

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

### Python Team Optimization
- `python models/output_teams/teams_optimisation.py` - Run genetic algorithm team optimization without Pikachu
- `python models/output_teams/teams_optimisation_with_pikachu.py` - Run genetic algorithm team optimization including Pikachu

### Python Dependencies
The Python optimization scripts require:
- pandas
- deap (Distributed Evolutionary Algorithms in Python)
- Additional standard library modules: random, math, re

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

**Optimization Layer** (`models/optimisation/`): SQL-based team selection logic
- `initial_top_6.sql` - Basic team ranking by total battle scores
- Future models to replace Python genetic algorithm logic with SQL implementations

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

### Python Genetic Algorithm Integration
The optimization scripts in `models/output_teams/` implement sophisticated team selection:
- **Genetic Algorithm**: Uses DEAP library for evolutionary optimization
- **Fitness Function**: Considers battle scores, difficulty ratings, TM conflicts, team diversity
- **Constraint Handling**: Resolves single-use TM conflicts through greedy assignment
- **Adaptive Parameters**: Population size and generations scale with Pokémon pool size
- **NoLedges Filtering**: Automatically excludes legendary Pokémon for certain run types
- **Multi-objective Scoring**: Balances individual matchup strength with team synergy

## Development Workflow
1. Update seed data in `seeds/` directory
2. Run `dbt seed` to load new data into DuckDB
3. Develop/modify models in appropriate layer directories (staging → intermediate → optimisation → tableau)
4. Test individual models with `dbt run --select <model_name>`
5. Run full pipeline with `dbt run` (builds all models and exports CSV files)
6. Execute Python optimization scripts to generate optimal teams (being migrated to SQL in optimisation layer)
7. Review results in generated CSV files and Tableau dashboard

## Performance Optimization Notes
**Current Known Inefficiencies (See TODO.md for optimization plan)**:
- Pokemon stats calculated multiple times across models instead of pre-calculated in staging
- Move availability logic duplicated via `get_move_sources()` macro calls
- Evolution chains recalculated repeatedly instead of materialized once
- Type effectiveness lookups repeated across models
- Battle analysis performs expensive calculations that could be optimized

## Important Technical Notes
- **Generation 1 Mechanics**: Damage calculations follow original RBY formulas exactly, including stat caps and rounding behavior
- **Performance Optimization**: All models use table materialization due to complex battle simulation calculations
- **Sprite Integration**: Uses sprite_base_url variable pointing to Pokemon Yellow Legacy ROM hack repository
- **TM Conflict Resolution**: Python scripts handle single-use TM allocation through greedy optimization
- **Battle Difficulty**: Uses custom difficulty ratings (Easy, Medium, Hard, Very Hard, Requires Specific Counter)
- **Data Export**: Tableau models automatically generate CSV files for dashboard consumption
- **Run Variants**: Supports multiple run types including standard and NoLedges (no legendary Pokémon)