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

## 2026-07-04 — Stale-schema fix (issue #15)

- Root cause: `data/create_database.py` used a cwd-relative db path, so "rebuilds" run from
  the repo root created/deleted a db in the **root** while dbt kept writing to
  `data/pkmn_yellow_legacy.db` — stale schemas (`optimisation.*`, old `main.*`, pre-rename
  `intermediate.*`) survived every rebuild. Path is now anchored to the script's directory.
- New guard: `dbt run-operation check_orphan_relations` diffs `information_schema.tables`
  against the manifest (models + seeds) and fails listing any orphans. Run it after
  renaming/deleting models. Excludes `dbt_test__audit` (dbt's store_failures schema).
- Verified: check flagged 52 orphans on the stale db; after clean rebuild
  (create_database.py → seed → build) it passes with 85 relations.

## 2026-07-04 — Canonical species_key (issue #17)

- Root cause of the "string-surgery join" bug class: within dbt every join uses the same
  `pokemon` string form consistently, so internal joins already work. The drift only bites at
  the **agent boundary**, where the sibling repo binds raw emulator species values against
  dbt's hyphenated/spaced names with ad-hoc `.replace()`/`REPLACE()`/`LOWER()` surgery.
- Fix: new `species_key()` macro (`UPPER(REGEXP_REPLACE(col,'[^A-Za-z0-9]','','g'))` →
  `NIDORANM`, `MRMIME`, `FARFETCHD`) emitted as an additive column on exactly the 5 boundary
  tables the agent reads: `stg_pkmn_stats`, `stg_pkmn_catch_rates`, `stg_pkmn_evolutions`
  (+`evolution_key`), `int_encounter_lookup`, `mart_trainer_counters` (trainer + counter keys).
  `unique`/`not_null` on `species_key` only where it's 1:1 with the species (stats, catch_rates);
  evolutions is not unique (branching evos) so no test there.
- Scoped deliberately (ponytail): threading the key through *every* species-bearing model is
  additive churn with no consumer — the internal joins already match. Map side needs nothing:
  nav models key on the `map_name` enum + `stg_nav_map_metadata.map_id_hex`, and #13 already
  fixed `int_encounter_lookup.nav_map_name`. Agent-side `.replace()` deletion is a **separate
  PR** in dbtPlaysPokemon.
- Verified: clean rebuild → seed → `dbt build` PASS=190 WARN=1 (pre-existing
  `assert_team_beats_all_opponents`) ERROR=0; `check_orphan_relations` OK (86 relations);
  sibling agent `pytest -q` 286 passed.

### Notes / gotchas
- The venv lives at `.venv/Scripts/` (CLAUDE.md's `env/Scripts/` reference is stale).
- The 3 `dash_*` models are disabled via `+enabled: false` in `dbt_project.yml`, so they do
  not build (relevant to success criterion #4 — they produce no rows while disabled).
- Disabled models keep their `refs` (by name) but have empty resolved `depends_on.nodes` in
  the manifest — resolve their lineage via `refs` when scripting against `target/manifest.json`.
