# 🔥 Pokémon Yellow Legacy dbt Project

[![Work in Progress](https://img.shields.io/badge/Status-Work%20in%20Progress-yellow)](https://github.com/wjsutton/pkmn_yellow_legacy_dbt)
[![dbt](https://img.shields.io/badge/dbt-1.0+-orange)](https://www.getdbt.com/)
[![Pokémon](https://img.shields.io/badge/Gotta%20Catch-'Em%20All-red)](https://pokemon.com)

> **⚠️ This repository is currently being refactored to make it more user-friendly. Documentation and setup instructions are being improved.**

A **dbt** project to analyse and model data from the **Pokémon Yellow Legacy** ROM hack, helping trainers optimise their journey through Kanto.

## 🎯 Project Overview

This project transforms raw Pokémon game data into analytical models that can help answer questions like:
- What's the optimal team composition for beating the game?
- Which Pokémon have the best stat distributions for specific roles?
- How do movesets evolve throughout the game progression?
- What are the most efficient routes for experience grinding?

The project leverages dbt's powerful transformation capabilities to create clean, tested, and documented datasets from Pokémon Yellow Legacy game data.

## 🚀 What is Pokémon Yellow Legacy?

Pokémon Yellow Legacy is a ROM hack created by TheSmithPlays that aims to fix and polish the original Pokémon Yellow while staying true to Generation 1's vision. This project analyzes data from this enhanced version of the classic game.

<a href="https://youtu.be/9yxjuwCJbjI?feature=shared">
📺 How to Play Pokémon Yellow Legacy
</a>

## 🏗️ Project Structure (Work in Progress)

The project is being restructured, but will include models for:

- **Raw Data Layer**: Seed tables added to duckdb with `dbt seed`
- **Staging Layer**: Cleaned and standardized data
- **Intermediate Layer**: Key tables for team optimisation
  - [Available Pokémon](/models/intermediate/int_pokemon_availability.sql)
  - [Trainer's Pokémon](/models/intermediate/int_trainer_roster.sql)
  - [Order of the Game](/models/intermediate/int_game_progression.sql)
  - [All Pokémon Matchups](/models/intermediate/int_battle_analysis.sql)
  - [Prep work for Python Optimisation Models](/models/intermediate/int_team_optimization.sql)

```
pkmn_yellow_legacy_dbt/
├── models/
│   ├── staging/          # Raw data cleanup and integrity testing
│   ├── intermediate/     # Key tables for team optimisation
│   ├── output_teams/     # Legacy team selection model 
│   ├── optimisation/     # Migration to new team selection
│   └── tableau/          # Tables for exposure layer
├── macros/             # Key metric calculations and helper functions
├── seeds/              # Source pokemon data files
└── docs/               # Project documentation
```

## 📈 Roadmap

- [ ] **Phase 1**: Refactor existing models for better usability
- [ ] **Phase 2**: Implement pokemon availablity check tests
- [ ] **Phase 3**: Create exposure layer
- [ ] **Phase 4**: Add documentation

## 🤝 Contributing

This project is currently under active development and refactoring. Contributions will be welcomed once the initial restructuring is complete!

### Ideas for Future Contributions:
- Ability to create a Mono-type run
- [Pokemon showdown](https://pokemonshowdown.com/) integration for better battle simulation models
- Applications for next Pokemon Legacy games: Crystal and Emerald 

## 📚 Resources

- [dbt Documentation](https://docs.getdbt.com/)
- [Pokémon Yellow Legacy ROM Hack](https://github.com/cRz-Shadows/Pokemon_Yellow_Legacy)
- [TheSmithPlays YouTube Channel](https://youtube.com/thesmithplays)

## 📝 License

This project is for educational and analytical purposes. Pokémon is a trademark of Nintendo/Game Freak/Creatures Inc.

## 💬 Contact

- **GitHub**: [@wjsutton](https://github.com/wjsutton)
- **Issues**: Please open an issue for questions or suggestions

---

*Gotta analyze 'em all!* 📊⚡

> **Note**: This README will be updated as the project refactoring progresses. Star the repo to stay updated on improvements!
