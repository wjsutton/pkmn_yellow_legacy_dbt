# TODO - Dashboard Data Prep

Prepping the data layer for a dashboard release.

## Project 1: Implement EXP System

### Done
- Added EXP growth rates, base EXP seeds and staging models
- Built `int_level_exp_requirements`, `int_pkmn_exp_data`, `int_pkmn_level_exp` intermediate models
- Built `int_stage_pokemon_costs` (per-pokemon per-stage fresh EXP cost, trade discounts, coverage metrics)
- Built `opt_min_exp_squads` (minimum-EXP teams via cheapest-counter assignment across 12 run variants)
- Created `calculate_transition_exp` and `greedy_pick_round` macros

### Next: EXP Gain from Defeating Trainers
- Calculate how much EXP the team earns from defeating each trainer in a stage
- Use `int_pkmn_level_exp.trainer_exp_yield` (already computed) combined with opponent pokemon levels
- Track cumulative EXP gained through the route to determine if the team can self-sustain levelling or needs wild grinding
- Compare EXP earned vs EXP required to identify grinding gaps per stage

## Project 2: Add Remaining Trainers

- Import non-mandatory trainers from source materials (optional route trainers)
- Import post-game trainers
- Extend `int_opponent_pokemon` and `int_battle_outcomes` to include these
- Decide how optional trainers factor into team optimisation (bonus EXP sources vs required coverage)

## Project 3: Map Data Verification

- Verify `stg_map_locations` coordinate data against actual game map
- Update/fix any incorrect or missing location coordinates
- Ensure all routes, towns, and dungeons have valid display names
- Prep map data for Tableau/dashboard visualisation layer

## Validation Issues

No outstanding issues.
