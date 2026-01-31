# Pokemon Yellow Legacy dbt Project
# Data Validation Questions

*Generated from early analysis Excel file comparison*

---

## Overview

This document contains validation questions derived from your early analysis Excel file (my_team_for_the_run.xlsx). The Excel data covered 6 different run configurations across 9 game stages, analyzing optimal team compositions against all mandatory trainers. Use these questions to validate your dbt project data, keeping in mind that exact values may differ due to calculation fixes, but the overall patterns and rankings should be similar.

---

## Run Configurations in Excel

The Excel file analyzed 6 run configurations combining Eeveelution choice with route options:

| Run Name | Description |
|----------|-------------|
| Flareon_Standard_NoPika_Ledges | Flareon evo, uses ledge shortcuts |
| Flareon_Standard_NoPika_NoLedges | Flareon evo, no ledge shortcuts |
| Jolteon_Standard_NoPika_Ledges | Jolteon evo, uses ledge shortcuts |
| Jolteon_Standard_NoPika_NoLedges | Jolteon evo, no ledge shortcuts |
| Vaporeon_Standard_NoPika_Ledges | Vaporeon evo, uses ledge shortcuts |
| Vaporeon_Standard_NoPika_NoLedges | Vaporeon evo, no ledge shortcuts |

---

## Section 1: Game Stage Structure & Trainer Coverage

### Q1: How many distinct game stages exist in the dbt project?

**Category:** Game Structure

**Query Approach:** Query opt_team_performance or int_battle_outcomes for DISTINCT game_stage values

**✅ Success Criteria:** Should have Badge_1 through Badge_8 plus Elite 4 (9 stages minimum). The Excel had exactly 9 stages. A 'Rematches' stage may also be present.

*Notes from Excel: Excel stages: Badge_1, Badge_2, Badge_3, Badge_4, Badge_5, Badge_6, Badge_7, Badge_8, Elite 4*

---

### Q2: Which trainers are included in each game stage?

**Category:** Trainer Coverage

**Query Approach:** Query int_battle_outcomes grouping by game_stage and listing distinct trainers

**✅ Success Criteria:** Badge_1 should include Brock, Rival battles. Badge_2 should have Misty + many route trainers. Badge_7 should have Blaine. Elite 4 should have Lorelei, Bruno, Agatha, Lance, and Champion variants.

*Notes from Excel: Badge_7 only had Blaine. Elite 4 had Lorelei, Bruno, Agatha, Lance + Champion_Flareon/Jolteon/Vaporeon + Rival_7 variants*

---

### Q3: Are Giovanni battles correctly staged?

**Category:** Trainer Coverage

**Query Approach:** Query for all Giovanni-related trainers and their game_stage assignments

**✅ Success Criteria:** Giovanni_1 should be Badge_4 (Rocket Hideout), Giovanni_2 should be Badge_6 (Silph Co), Giovanni (gym) should be Badge_8

*Notes from Excel: Excel showed Giovanni_1 at Badge_4, Giovanni_2 at Badge_6, Giovanni at Badge_8*

---

## Section 2: Pokemon Availability by Stage

### Q4: What Pokemon are available at Badge_1?

**Category:** Pokemon Availability

**Query Approach:** Query int_pokemon_availability or opt_team_performance WHERE game_stage = 'Badge_1'

**✅ Success Criteria:** Should include Mankey, Pikachu, Poliwag as early-game options. All should be at level 12 (or appropriate early level cap).

*Notes from Excel: Excel Badge_1 Pokemon: Mankey_lvl_12, Pikachu_lvl_12, Poliwag_lvl_12, Vulpix_lvl_12*

---

### Q5: Do legendary birds appear at the correct stages?

**Category:** Pokemon Availability

**Query Approach:** Check when Articuno, Zapdos, Moltres become available in int_pokemon_availability

**✅ Success Criteria:** Articuno should appear around Badge_8 (55) or Elite 4 (65). Zapdos should be available from Badge_8. Moltres at Elite 4 level 65.

*Notes from Excel: Excel showed Articuno_lvl_55 at Badge_8, Articuno_lvl_65/Zapdos_lvl_65/Moltres_lvl_65 at Elite 4*

---

### Q6: Do Ledges vs NoLedges runs have different Pokemon pools?

**Category:** Pokemon Availability - Route Variants

**Query Approach:** Compare player_pkmn_id lists between runs with/without Ledges suffix

**✅ Success Criteria:** Ledges runs should have: Articuno, Zapdos, Moltres, Tentacruel, Dewgong at higher stages. NoLedges should have: Alakazam, Pidgeot, Jynx, Blastoise, Hypno as alternatives.

*Notes from Excel: Ledges-only: Articuno_lvl_55/65, Zapdos_lvl_55/65, Moltres_lvl_65, Tentacruel_lvl_65. NoLedges-only: Alakazam_lvl_55/65, Pidgeot_lvl_55/65, Jynx_lvl_65*

---

### Q7: Are Eeveelutions correctly exclusive to their respective runs?

**Category:** Pokemon Availability

**Query Approach:** Check that Jolteon only appears in Jolteon runs, Flareon in Flareon runs, etc.

**✅ Success Criteria:** Jolteon should only be a player option in Jolteon runs. Champion battles should match (Champion_Jolteon only in Jolteon runs).

*Notes from Excel: Excel correctly segregated Champion_Flareon, Champion_Jolteon, Champion_Vaporeon to their respective run types*

---

## Section 3: Moveset Accuracy

### Q8: Does Pikachu have level-appropriate moves at each stage?

**Category:** Movesets

**Query Approach:** Query int_pokemon_movesets for Pikachu at different levels

**✅ Success Criteria:** Pikachu_lvl_12 should have Quick Attack, Thundershock (basic). Pikachu_lvl_21 should add Thunderpunch, Mega Punch. Pikachu_lvl_43 should have Thunder, Thunderbolt, Surf (HM).

*Notes from Excel: Excel Pikachu moves: lvl_12: Quick Attack, Thundershock | lvl_21: Mega Punch, Quick Attack, Thunderpunch, Thundershock | lvl_43: Mega Kick, Submission, Surf, Thunder, Thunderbolt*

---

### Q9: Do Water-types have Surf available after the appropriate badge?

**Category:** Movesets

**Query Approach:** Check when Surf appears in movesets for Gyarados, Starmie, Poliwrath, etc.

**✅ Success Criteria:** Surf (HM03) requires Soul Badge from Koga (Badge_5). Water Pokemon should have Surf in their movesets from Badge_6 onwards.

*Notes from Excel: Excel showed Surf on Gyarados_lvl_50 (Badge_6), Starmie_lvl_50 (Badge_6), etc.*

---

### Q10: Does Alakazam have Psychic available?

**Category:** Movesets

**Query Approach:** Query moves for Alakazam across different level variants

**✅ Success Criteria:** Alakazam learns Psychic via level-up. Should be available at all stages where Alakazam is present.

*Notes from Excel: Excel Alakazam moves included: Psychic, Psybeam, Mega Kick, Mega Punch, Submission, Take Down*

---

### Q11: Are TM moves like Earthquake available to appropriate Pokemon?

**Category:** Movesets - TMs

**Query Approach:** Check if Earthquake appears in movesets for Ground-types like Nidoking, Dugtrio

**✅ Success Criteria:** Earthquake (TM26) should be available to Nidoking, Dugtrio, Sandslash. Should appear after TM is obtainable.

*Notes from Excel: Excel showed Nidoking with Earthquake at Badge_5 (lvl_43) against Koga*

---

## Section 4: Battle Score Patterns

### Q12: What is the metric range in battle calculations?

**Category:** Battle Scores

**Query Approach:** Query MIN, MAX, AVG of battle_score from int_battle_outcomes

**✅ Success Criteria:** Scores should roughly range from negative (losing matchups) to ~2.0 (dominant wins). Mean around 1.0-1.2. Some negative scores are expected for bad matchups.

*Notes from Excel: Excel metric_total: Min=-0.74, Max=1.99, Mean=1.07, Median=1.15*

---

### Q13: Is Mankey the best counter for Brock?

**Category:** Battle Scores - Brock

**Query Approach:** Query best battle_score for trainer='Brock' grouped by player Pokemon

**✅ Success Criteria:** Mankey with Low Kick should have highest scores against Brock (Fighting vs Rock). Score should be around 1.26 or higher.

*Notes from Excel: Excel: Mankey Low Kick vs Brock_Geodude = 1.2639, Poliwag Bubble vs Brock_Geodude = 1.1278*

---

### Q14: Is Pikachu effective against Misty?

**Category:** Battle Scores - Misty

**Query Approach:** Query battle scores for Misty matchups

**✅ Success Criteria:** Pikachu with Thunderpunch should excel. Expect scores ~1.45 vs Goldeen, ~1.39 vs Psyduck. Starmie should be much harder.

*Notes from Excel: Excel: Pikachu Thunderpunch vs Misty_Goldeen = 1.4545, vs Misty_Psyduck = 1.3866, vs Misty_Starmie = 0.0833 (tough!)*

---

### Q15: Is Lt. Surge's Raichu a significant challenge?

**Category:** Battle Scores - Lt. Surge

**Query Approach:** Query battle scores against Lt._Surge's Raichu

**✅ Success Criteria:** Raichu should be extremely difficult. Best options show LOW or NEGATIVE scores. This was a known hard fight in the Excel.

*Notes from Excel: Excel: ALL matchups vs Lt._Surge_Raichu were negative! Best was Magnemite Sonicboom at -0.026*

---

### Q16: Is Ninetales effective against Erica's Grass gym?

**Category:** Battle Scores - Erica

**Query Approach:** Query battle scores for Erica_4 matchups with Ninetales

**✅ Success Criteria:** Ninetales with Flamethrower should dominate. Expect scores: ~1.51 vs Ivysaur, ~1.39 vs Tangela, ~1.32 vs Gloom, ~1.25 vs Victreebel.

*Notes from Excel: Excel confirmed Ninetales Flamethrower as top choice: Ivysaur=1.5103, Tangela=1.3935, Gloom=1.3197, Victreebel=1.2488*

---

### Q17: Which Pokemon performs best against Koga?

**Category:** Battle Scores - Koga

**Query Approach:** Query top battle_score values for trainer='Koga_5'

**✅ Success Criteria:** Alakazam with Psychic should be top tier (~1.35 vs Venomoth, ~1.27 vs Golbat). Nidoking Earthquake good vs Muk (~1.30).

*Notes from Excel: Excel: Alakazam Psychic vs Koga_5_Venomoth=1.3475, Nidoking Earthquake vs Koga_5_Muk=1.2999*

---

### Q18: Are Water types dominant against Blaine's Fire gym?

**Category:** Battle Scores - Blaine

**Query Approach:** Query battle scores for trainer='Blaine'

**✅ Success Criteria:** Tentacruel/Starmie with Hydro Pump should excel. Aerodactyl Rock Slide good vs Charizard (~1.50).

*Notes from Excel: Excel: Tentacruel Hydro Pump vs Blaine_Ninetales=1.5427, Starmie Hydro Pump vs Blaine_Rapidash=1.5246, Aerodactyl Rock Slide vs Blaine_Charizard=1.5050*

---

### Q19: Is Giovanni's Dugtrio problematic?

**Category:** Battle Scores - Giovanni (Gym)

**Query Approach:** Query battle scores specifically for Giovanni_Dugtrio

**✅ Success Criteria:** Dugtrio should show NEGATIVE scores for many matchups, especially Flying types. This was the worst matchup in the Excel data.

*Notes from Excel: Excel: Giovanni_Dugtrio had the worst matchups - Pidgeot Fly=-0.7429, Zapdos Fly=-0.7214, Zapdos Drill Peck=-0.6857*

---

## Section 5: Elite 4 Battle Analysis

### Q20: Are Electric types effective against Lorelei?

**Category:** Elite 4 - Lorelei

**Query Approach:** Query best matchups against Lorelei's team

**✅ Success Criteria:** Jolteon/Zapdos with Thunder should dominate. Cloyster particularly vulnerable (~1.78 score).

*Notes from Excel: Excel: Jolteon Thunder vs Lorelei_Cloyster=1.7751, Zapdos Thunder=1.7180, Moltres Fire Blast vs Lorelei_Jynx=1.6313*

---

### Q21: How effective are Flying/Psychic types against Bruno?

**Category:** Elite 4 - Bruno

**Query Approach:** Query battle scores for Bruno's Fighting types

**✅ Success Criteria:** Zapdos Thunder should excel vs Poliwrath (~1.86). Water moves dominate Onix (~1.83). Moltres Sky Attack good vs Hitmonlee (~1.80).

*Notes from Excel: Excel: Zapdos Thunder vs Bruno_Poliwrath=1.8643, Starmie Surf vs Bruno_Onix=1.8325*

---

### Q22: What counters Agatha's Ghost types?

**Category:** Elite 4 - Agatha

**Query Approach:** Query matchups against Agatha_Gengar

**✅ Success Criteria:** Agatha's Gengar should have LOW positive or negative scores (Ghost immunity issues). Zapdos Thunder vs Golbat should be strong (~1.84).

*Notes from Excel: Excel: Agatha_Gengar_1 best score was only 1.37 (Zapdos Thunder). Agatha_Golbat much easier at 1.84*

---

### Q23: Is Articuno the Lance counter?

**Category:** Elite 4 - Lance

**Query Approach:** Query battle scores for Lance matchups with Ice moves

**✅ Success Criteria:** Articuno Blizzard should dominate Dragon types. Expect ~1.79 vs Dragonite. Zapdos Thunder strong vs Gyarados (~1.78).

*Notes from Excel: Excel: Articuno Blizzard vs Lance_Dragonite_1=1.7888, vs Lance_Dragonite_2=1.7472, Zapdos Thunder vs Lance_Gyarados=1.7796*

---

### Q24: Do Champion teams vary by Eeveelution path?

**Category:** Elite 4 - Champion

**Query Approach:** Query distinct trainer_pkmn_id values for Champion battles

**✅ Success Criteria:** Champion_Flareon should have: Sandshrew, Magneton, Flareon, Dutrio, Cloyster, Alakazam. Champion_Jolteon/Vaporeon have different teams.

*Notes from Excel: Excel confirmed distinct Champion teams: Flareon path had Sandshrew, Magneton, Flareon, Dutrio, Cloyster, Alakazam*

---

## Section 6: Consistency Checks

### Q25: Do Pokemon levels match the stage level caps?

**Category:** Consistency

**Query Approach:** Query player_pkmn_level grouped by game_stage

**✅ Success Criteria:** Badge_1=12, Badge_2=21, Badge_3=24, Badge_4=35, Badge_5=43, Badge_6=50, Badge_7=53, Badge_8=55, Elite4=65

*Notes from Excel: Excel levels matched this pattern exactly*

---

### Q26: Are the 'Ledges' Pokemon from early-accessible areas?

**Category:** Consistency

**Query Approach:** Check the source locations of Ledges-exclusive Pokemon

**✅ Success Criteria:** Ledges runs allow backtracking via ledges in Power Plant/Seafoam. Should enable Articuno, Zapdos access earlier.

*Notes from Excel: Ledges runs had legendary birds; NoLedges had alternatives like Alakazam, Pidgeot*

---

### Q27: Is there trainer Pokemon data for all gym leaders?

**Category:** Consistency

**Query Approach:** Query int_opponent_pokemon for all gym leader trainer entries

**✅ Success Criteria:** Should have complete data for: Brock, Misty, Lt. Surge, Erica, Koga, Sabrina, Blaine, Giovanni (gym)

*Notes from Excel: All 8 gym leaders were present in Excel data*

---

## Section 7: Recommended Team Patterns

### Q28: What team is recommended for Badge_5 (Koga)?

**Category:** Team Composition

**Query Approach:** Query opt_team_performance WHERE game_stage='Badge_5' ORDER BY stage_rank

**✅ Success Criteria:** Should recommend Alakazam (Psychic vs Poison), Nidoking (Earthquake), Gyarados. Pinsir and Pikachu viable options.

*Notes from Excel: Excel Badge_5 team: Alakazam_lvl_43, Gyarados_lvl_43, Nidoking_lvl_43, Pikachu_lvl_43, Pinsir_lvl_43, Raticate_lvl_43*

---

### Q29: What team is recommended for Badge_7 (Blaine)?

**Category:** Team Composition

**Query Approach:** Query opt_team_performance WHERE game_stage='Badge_7' ORDER BY stage_rank

**✅ Success Criteria:** Water types should dominate: Starmie, Tentacruel. Aerodactyl valuable for Rock moves vs Charizard.

*Notes from Excel: Excel Badge_7 team: Aerodactyl_lvl_53, Dewgong_lvl_53, Starmie_lvl_53, Tentacruel_lvl_53*

---

### Q30: What is the recommended Elite 4 team in Flareon runs?

**Category:** Team Composition

**Query Approach:** Query opt_team_performance WHERE game_stage='Elite 4' for Flareon path

**✅ Success Criteria:** Should include Articuno (vs Lance dragons), Jolteon/Zapdos (Electric coverage), Gyarados, Moltres.

*Notes from Excel: Excel Elite 4 (Flareon): Articuno_lvl_65, Gyarados_lvl_65, Jolteon_lvl_65, Moltres_lvl_65, Nidoking_lvl_65, Zapdos_lvl_65*

---

## Key Validation Benchmarks

Use these specific values as rough benchmarks when validating your dbt calculations:

| Matchup | Move | Excel Score | Pattern |
|---------|------|-------------|---------|
| Mankey vs Brock_Geodude | Low Kick | 1.2639 | High |
| Pikachu vs Misty_Goldeen | Thunderpunch | 1.4545 | High |
| ANY vs Lt.Surge_Raichu | Any | -0.026 (best!) | Negative |
| Ninetales vs Erica_Ivysaur | Flamethrower | 1.5103 | High |
| Alakazam vs Koga_Venomoth | Psychic | 1.3475 | High |
| Tentacruel vs Blaine_Ninetales | Hydro Pump | 1.5427 | High |
| ANY vs Giovanni_Dugtrio | Ground moves | -0.64 to -0.74 | Negative |
| Articuno vs Lance_Dragonite | Blizzard | 1.7888 | Very High |
| Zapdos vs Bruno_Poliwrath | Thunder | 1.8643 | Very High |

---

## Notes on Interpretation

1. **Exact values will differ** due to calculation fixes, but relative rankings should be similar.

2. **Scores above 1.5** indicate dominant matchups where the player Pokemon clearly wins.

3. **Scores below 0.5** indicate unfavorable matchups. Negative scores mean the player loses.

4. **Lt. Surge's Raichu and Giovanni's Dugtrio** should remain challenging matchups in any calculation system.

5. **Type effectiveness should drive major score differences** (4x effective should show much higher scores).
