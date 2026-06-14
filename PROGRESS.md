# PROGRESS.md

Cross-iteration memory: learnings and structural decisions.

## Current model architecture (5 folders)

`models/` contains exactly five folders, no files outside them:

| Folder | Purpose | Naming |
|--------|---------|--------|
| `staging/` | Light cleanup of seed CSVs. Tests: unique + not_null on PKs only. | `stg_*` |
| `intermediate/` | Building-block models (availability, movesets, opponents, stats, EXP source data, encounter lookup, map/navigation). No tests (except pre-existing PK tests on `int_navigation_guide` / `int_map_connections`). | `int_*` |
| `marts/` | Final analytical layer: battle outcomes, costs, and team selection. Tests: max 6 per team, single-use TM uniqueness. | `mart_*` |
| `dashboard/` | Tableau-ready datasets. Currently `+enabled: false` in `dbt_project.yml`. | `dash_*` |
| `semantic/` | Semantic layer (no materialized models): `_catch_semantic.yml` catch-domain view. | n/a |

`marts/` has 6 models (< 10 intermediate models), satisfying "fewer files in the final layer".

## 2026-06-13 — Layer restructure (optimisation → marts, new semantic folder)

Moved the higher-order models out of intermediate/optimisation into a unified `marts/` layer
and split the catch semantic view into its own `semantic/` folder.

- **→ `marts/` (renamed `int_*`/`opt_*` to `mart_*`):**
  - `int_battle_outcomes` → `mart_battle_outcomes`
  - `int_pkmn_level_exp` → `mart_pkmn_level_exp`
  - `int_stage_pokemon_costs` → `mart_stage_pokemon_costs`
  - `opt_team_performance` → `mart_team_performance`
  - `opt_recommended_teams` → `mart_recommended_teams`
  - `opt_min_exp_squads` → `mart_min_exp_squads`
  - The 3 moved `int_*` models were the only intermediate models that referenced other
    intermediate models; intermediate is now a flatter building-block layer.
- **`optimisation/` folder removed.** Its `_semantic.yml` → `marts/_semantic.yml`; its
  `_schema.yml` descriptions merged into the new `marts/_schema.yml` (alongside the 3
  relocated `int_*` description blocks).
- **`semantic/` folder created.** `marts/_catch_semantic.yml` → `semantic/_catch_semantic.yml`.
- **All `ref()` calls updated** across moved models, dashboard consumers, singular tests,
  and analyses. `dbt_project.yml` model config: `optimisation` block replaced with `marts`
  (`+schema: marts`). No `models:` config needed for `semantic/` (no materialized models).
- **Verified:** `dbt build` → PASS=125, ERROR=0. `assert_max_6_per_team` and
  `assert_single_use_tms_unique` pass. `assert_team_beats_all_opponents` WARNs (75 rows) —
  pre-existing, `severity='warn'`, unrelated to the move.

### Notes / gotchas
- The venv lives at `.venv/Scripts/` (CLAUDE.md's `env/Scripts/` reference is stale).
- The 3 `dash_*` models are disabled via `+enabled: false` in `dbt_project.yml`, so they do
  not build (relevant to success criterion #4 — they produce no rows while disabled).
- Disabled models keep their `refs` (by name) but have empty resolved `depends_on.nodes` in
  the manifest — resolve their lineage via `refs` when scripting against `target/manifest.json`.
