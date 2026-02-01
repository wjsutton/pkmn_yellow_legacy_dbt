# TODO - Dashboard Data Prep

Prepping the data layer for a dashboard release.

## Project 1: Implement EXP System

### Done
- Added EXP growth rates, base EXP seeds and staging models
- Built `int_level_exp_requirements`, `int_pkmn_exp_data`, `int_pkmn_level_exp` intermediate models
- Built `int_stage_pokemon_costs` (per-pokemon per-stage fresh EXP cost, trade discounts, coverage metrics)
- Built `opt_min_exp_squads` (minimum-EXP teams via cheapest-counter assignment across 12 run variants)
- Created `calculate_transition_exp` and `greedy_pick_round` macros

### Done: EXP Gain from Defeating Trainers
- Added EXP earned calculation to `opt_min_exp_squads` — assigns opponents to cheapest team member, sums `trainer_exp_yield` per fighter
- New columns: `exp_earned`, `battles_fought`, `exp_deficit`, `exp_status`
- Status categories: Free (trade at cap), Self-sustaining, Needs minor grinding, Needs significant grinding
- Key findings: ~12% of team members self-sustain, ~11% need minor grinding, ~64% need significant grinding, ~12% are free trades

## Project 2: Add Remaining Trainers

### Done
- Imported non-mandatory trainers (2,750 rows) — seed, source, staging model with PK tests
- Imported post-game trainers (360 rows) — seed, source, staging model with PK tests
- Extended `int_opponent_pokemon` with UNION ALLs for `stg_trainers_non_mandatory` and `stg_trainers_postgame`
- `int_battle_outcomes` automatically includes all trainer types via dependency on `int_opponent_pokemon`
- All trainer types flow through to `opt_min_exp_squads` and `opt_recommended_teams` for team selection and EXP calculations

## Project 3: Map Data Verification

- Verify `stg_map_locations` coordinate data against actual game map
- Update/fix any incorrect or missing location coordinates
- Ensure all routes, towns, and dungeons have valid display names
- Prep map data for Tableau/dashboard visualisation layer

## Validation Issues

No outstanding issues.
