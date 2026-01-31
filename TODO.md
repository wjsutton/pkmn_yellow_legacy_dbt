# TODO - Validation Issues

Issues identified from validating dbt output against `bug_reports/pokemon_yellow_dbt_validation_questions.md` and `bug_reports/compass_artifact_...text_markdown.md`.

---

## Build Performance

### 6. `int_battle_outcomes` is the build bottleneck

**Severity:** High

`int_battle_outcomes` takes ~79 seconds to build, accounting for ~98% of total build time. Every other model runs in under 1 second. The model performs a massive cross-join of all player pokemon/moves against all trainer pokemon/moves per game stage, then computes damage calculations for every matchup. The result feeds into both optimisation models.

| Model | Build Time |
|-------|-----------|
| 16x staging models | < 0.15s each |
| `int_pokemon_availability` | 0.37s |
| `int_pokemon_movesets` | 0.12s |
| `int_opponent_pokemon` | 0.13s |
| `int_pokemon_stats` | 0.10s |
| **`int_battle_outcomes`** | **78.78s** |
| `opt_team_performance` | 0.42s |
| `opt_recommended_teams` | 0.56s |

**Possible mitigations:** Pre-filter moves to best-per-type before the cross-join; reduce the join cardinality by only matching pokemon that are available at the same game stage; materialise intermediate CTEs.

**Affected models:** `int_battle_outcomes`

---

## Model Logic Issues

### 1. Eeveelution exclusivity not enforced for player pokemon

**Severity:** High
**Source:** Validation Q7

All three Eeveelutions (Jolteon, Flareon, Vaporeon) appear as player pokemon in every run variant. The run variant filtering only excludes rival/champion opponents -- it does not restrict which Eeveelution the player can use. In the game, you receive one Eevee and evolve it into one Eeveelution per playthrough.

**Result:** Jolteon dominates most runs because it is the strongest Electric type, regardless of which rival path is selected.

**Affected models:** `opt_recommended_teams`, `int_pokemon_availability`

---

### 2. Battle score scale capped at 0-1

**Severity:** Medium
**Source:** Validation Q12

Battle scores are capped between roughly -1.5 and 1.0. The original Excel analysis used a wider range (approximately -0.74 to 1.99), which allowed differentiation between "comfortable win" and "dominant win." With the current scale, many strong matchups cluster at exactly 1.0 with no separation.

**Result:** Team selection loses granularity at the top end. A 4x super-effective OHKO scores the same as a 2x super-effective 2HKO.

**Affected models:** `int_battle_outcomes` (via `calculate_battle_outcome` macro)

---

### 3. `is_gym_leader` flag is overloaded

**Severity:** Low
**Source:** Validation Q27

The `is_gym_leader` flag is set to 1 for all trainers sourced from `stg_trainers_gym_leaders`, which includes Rivals, Elite 4 members, Jessie & James, and Giovanni side-battles -- not just the 8 gym leaders. This inflates the gym leader weighting multiplier (3x) in `opt_team_performance` for trainers that aren't actually gym leaders.

**Result:** Team scoring over-weights non-gym boss battles.

**Affected models:** `int_opponent_pokemon`, `opt_team_performance`

---

### 4. Badge_7 scoring collapse

**Severity:** Medium
**Source:** Validation Q29

Badge_7 has only one trainer (Blaine). The scoring system rewards being the "best option" against each opponent pokemon, so only Starmie and Tentacruel receive meaningful scores. All other pokemon score 0.00 and are ranked as "Weak," even if they would perform adequately against Blaine.

**Result:** Badge_7 team recommendations are essentially empty beyond positions 1-2.

**Affected models:** `opt_team_performance`

---

### 5. Giovanni's Dugtrio not punishing enough

**Severity:** Low
**Source:** Validation Q19

The Excel analysis showed deeply negative scores for Giovanni's Dugtrio (best was -0.64 to -0.74). The dbt model shows positive scores around 0.70 for water types like Lapras and Poliwrath. The difficulty signal for this notoriously hard matchup is much weaker than expected.

**Result:** Team recommendations may underestimate the threat of Giovanni's Dugtrio at Badge_8.

**Affected models:** `int_battle_outcomes`

---

## Seed Data Discrepancies (vs Compass Validation Guide)

The following discrepancies were found between the compass validation guide and the actual seed/model data. Either the seed data or the guide could be wrong -- each needs verification against the game.

### 7. Champion_Flareon has Sandshrew at level 60 (should be Sandslash)

**Severity:** High

Sandshrew evolves into Sandslash at level 22. The Champion_Flareon trainer has a Sandshrew at level 60, which is impossible in normal gameplay. This is almost certainly a seed data error -- the pokemon should be Sandslash.

**Affected data:** `seeds/trainers_gym_leaders.csv`

---

### 8. Erika's team composition differs from guide

**Severity:** Medium

| Guide says | Data has |
|------------|----------|
| Weepinbell lvl 31 | Ivysaur lvl 31 |
| Tangela lvl 33 | Tangela lvl 33 |
| Gloom lvl 34 | Victreebel lvl 34 |
| Vileplume lvl 35 (ace) | Gloom lvl 35 (ace) |

Two of four pokemon differ. Needs verification against the game.

**Affected data:** `seeds/trainers_gym_leaders.csv`

---

### 9. Giovanni gym has Persian instead of Blastoise

**Severity:** Medium

The guide states Giovanni's gym team includes Blastoise to counter Ground/Water counters. The seed data shows Persian lvl 55 instead. Giovanni_2 (Silph Co.) also has Persian lvl 47. Needs verification -- Persian and Blastoise serve very different strategic roles.

**Affected data:** `seeds/trainers_gym_leaders.csv`

---

### 10. Rival 3 and 4 team composition differences

**Severity:** Medium

**Rival 3:**
| Guide says | Data has |
|------------|----------|
| Raticate lvl 15 | Rattata lvl 15 |
| Ivysaur lvl 15 | Bellsprout lvl 15 |

**Rival 4:**
| Guide says | Data has |
|------------|----------|
| Ivysaur lvl 22 | Weepinbell lvl 22 |
| Sandslash lvl 21 | Sandshrew lvl 21 |

The data consistently shows unevolved forms where the guide shows evolved forms. This could indicate the seed data is from a different version of the ROM hack, or the guide is inaccurate.

**Affected data:** `seeds/trainers_mandatory.csv`, `seeds/trainers_gym_leaders.csv`

---

### 11. Rival 6 Jolteon team completely different from guide

**Severity:** Medium

| Guide says (Silph Co. lvl 32-35) | Data has (Badge_6 lvl 43-46) |
|-----------------------------------|-------------------------------|
| Fearow 34 | Parasect 43 |
| Dewgong 32 | Rhydon 43 |
| Exeggcute 32 | Alakazam 44 |
| Kadabra 33 | Gyarados 44 |
| Jolteon 35 | Jolteon 46 |

The team composition and levels are entirely different. This is likely because the guide describes Rival 6 at an earlier game point (Silph Co., before gym 4-6), while the data has it at Badge_6 with dynamic scaling applied. The question is whether the seed data reflects the correct team for the game_stage it's assigned to.

**Affected data:** `seeds/trainers_gym_leaders.csv`

---

### 12. Sabrina has 5 pokemon, guide says 4

**Severity:** Low

The guide lists 4 pokemon for Sabrina (Abra, Mr. Mime, Hypno, Alakazam). The data shows 5: Hypno lvl 48, Mr-mime lvl 49, Alakazam lvl 50, Abra lvl 50, **Kadabra lvl 50** (extra). This may be correct if the data reflects a different gym order (fought as 6th = harder).

**Affected data:** `seeds/trainers_gym_leaders.csv`

---

### 13. Onix speed stat: 85 vs guide's claim of 95

**Severity:** Low

The guide states Onix was buffed to 95 Speed. The seed data shows 85 Speed. The other stat buffs match (HP 75, Atk 80, Spc 65). Either the guide has the wrong speed value or the seed data is 10 points off.

**Affected data:** `seeds/pkmn_stats.csv`

---

### 14. Poliwhirl evolution method differs

**Severity:** Low

The guide states Poliwhirl evolves at level 18 (changed from 25). The seed data shows Poliwhirl evolves via Water Stone, with no level-based evolution. Needs verification against the game.

**Affected data:** `seeds/pkmn_evolutions.csv`

---

### 15. Pin Missile power appears very low

**Severity:** Low

The seed data has Pin Missile at 6 power per hit (2-5 hits). The guide claims it was buffed to 20 per hit (+15% accuracy). At 6 per hit, Pin Missile averages 21 total damage, which would make it weaker than the original Gen 1 version (14 per hit x 3 avg = 42). This seems like a seed data error.

**Affected data:** `seeds/moves_stats.csv`

---

### 16. Moltres location: Victory Road 3F vs guide's 2F

**Severity:** Low

The guide states Moltres is on Victory Road 2F. The seed data places it on VictoryRoad3F. Minor location discrepancy -- does not affect availability timing.

**Affected data:** `seeds/pkmn_encounter_areas.csv`
