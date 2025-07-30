# 🔥 Pokémon Yellow Legacy dbt Project

[![dbt](https://img.shields.io/badge/dbt-1.9+-orange)](https://www.getdbt.com/)
[![DuckDB](https://img.shields.io/badge/DuckDB-Latest-blue)](https://duckdb.org/)
[![Pokémon](https://img.shields.io/badge/Gotta%20Catch-'Em%20All-red)](https://pokemon.com)

A **dbt** project analyzing Pokémon Yellow Legacy ROM hack data to optimize team compositions for beating the game. The project uses DuckDB as the data warehouse and SQL-based optimization models for high-performance team selection (migrated from Python genetic algorithms).

## 🎯 Project Overview

This project transforms raw Pokémon game data into analytical models that answer: **What's the optimal team composition for beating Pokémon Yellow Legacy?**

Key features:
- ✅ **SQL-based optimization** (99%+ performance improvement over genetic algorithms)
- ✅ **Generation 1 battle mechanics** with exact damage calculations
- ✅ **Multi-variant support** (Standard, NoLedges, Pikachu variants)
- ✅ **TM conflict resolution** using greedy assignment algorithms
- ✅ **Comprehensive testing suite** with 236 data quality tests
- ✅ **Tableau integration** for visualization and analysis

### 🚀 What is Pokémon Yellow Legacy?

Pokémon Yellow Legacy is a ROM hack created by TheSmithPlays that aims to fix and polish the original Pokémon Yellow while staying true to Generation 1's vision. This project analyses data from this enhanced version of the classic game.

<a href="https://youtu.be/9yxjuwCJbjI?feature=shared">
📺 How to Play Pokémon Yellow Legacy
</a>

## 🚀 Quick Start

### Prerequisites
- Python 3.8+
- dbt-duckdb adapter
- DuckDB

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/wjsutton/pkmn_yellow_legacy_dbt.git
   cd pkmn_yellow_legacy_dbt
   ```

2. **Install dependencies**
   ```bash
   pip install dbt-duckdb
   ```

3. **Create the database**
   ```bash
   cd data
   python create_database.py
   cd ..
   ```

4. **Run the pipeline**
   ```bash
   dbt deps    # Install dbt packages
   dbt seed    # Load seed data
   dbt run     # Build all models
   dbt test    # Run data quality tests
   ```

### Key Commands
- `dbt run --select staging+` - Build staging models and dependencies
- `dbt run --select models/optimisation/` - Build optimization models only
- `dbt test --select models/staging/` - Test staging layer
- `dbt clean` - Remove target/ and dbt_packages/ directories

## 🏗️ Project Architecture

```
pkmn_yellow_legacy_dbt/
├── models/
│   ├── staging/          # Cleaned source data (stg_*)
│   ├── intermediate/     # Core business logic (int_*) 
│   ├── optimisation/     # Team optimization models (opt_*)
│   └── tableau/          # Dashboard output tables
├── macros/               # Generation 1 battle mechanics
├── seeds/                # Raw CSV data files
├── data/                 # DuckDB database
└── dashboard_assets/     # Tableau CSV exports
```

### Data Flow
1. **Seeds** → Raw game data (Pokémon stats, moves, trainers, encounters)
2. **Staging** → Cleaned data with basic transformations
3. **Intermediate** → Battle analysis and team building preparation
4. **Optimization** → SQL-based team selection with variants
5. **Tableau** → Dashboard-ready output with CSV exports

## 🎮 Output

The project generates optimal 6-Pokémon teams for each game stage with multiple variants:

- **Standard Run** - All Pokémon available
- **NoLedges Run** - Excludes legendary Pokémon (Moltres, Articuno, Zapdos, Mewtwo, Mew)
- **Pikachu Variants** - Teams that include or exclude Pikachu

Results include:
- Individual Pokémon performance scores
- TM allocation and conflict resolution
- Battle matchup analysis
- Team composition recommendations
- Difficulty assessments for each trainer

## 📊 Performance

**Before (Python genetic algorithms):**
- 12+ hour execution time
- Probabilistic results (varied between runs)
- Complex maintenance and debugging

**After (SQL optimization models):**
- Sub-minute execution time (99%+ improvement)
- Deterministic optimal results
- Integrated with dbt pipeline
- Comprehensive testing and validation

## 🔧 Technical Highlights

### Generation 1 Battle Mechanics
- Exact Red/Blue/Yellow damage formulas
- Type effectiveness calculations
- STAB (Same Type Attack Bonus) handling
- Special move mechanics (Sonicboom, Dragon Rage, etc.)

### Optimization Features
- Greedy TM allocation algorithm
- Difficulty-based scoring penalties
- Multi-objective team composition
- Constraint handling for single-use items

### Data Quality
- 236 comprehensive tests
- Referential integrity validation
- Business logic verification
- Performance monitoring

## 🤝 Contributing

Contributions are welcome! Here are some ideas:

### Enhancement Ideas
- **Mono-type runs** - Teams restricted to single types
- **Nuzlocke support** - Rules for permadeath gameplay
- **Speed run optimization** - Minimize time rather than difficulty
- **Pokemon Showdown integration** - Enhanced battle simulation
- **Other ROM hacks** - Crystal Legacy, Emerald Legacy support
- **Move tutors** - Additional move sources beyond TMs
- **Held items** - Generation 2+ item mechanics

### Development
1. Fork the repository
2. Create a feature branch
3. Make changes and add tests
4. Submit a pull request

See `CLAUDE.md` for detailed development guidelines. 

## 📚 Resources

- [dbt Documentation](https://docs.getdbt.com/)
- [DuckDB Documentation](https://duckdb.org/docs/)
- [Pokémon Yellow Legacy ROM Hack](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy)
- [TheSmithPlays YouTube Channel](https://youtube.com/thesmithplays)
- [Generation 1 Mechanics](https://bulbapedia.bulbagarden.net/wiki/Generation_I)

## 📁 Key Files

- `CLAUDE.md` - Detailed project documentation and development guide
- `models/optimisation/opt_teams_final.sql` - Main team selection output
- `macros/calculate_damage_rby.sql` - Generation 1 damage formula
- `dashboard_assets/data/` - CSV exports for Tableau

## 💬 Contact

- **GitHub**: [@wjsutton](https://github.com/wjsutton)
- **Issues**: Open an issue for questions, bugs, or feature requests

---

*Built with ❤️ for the Pokémon community*
