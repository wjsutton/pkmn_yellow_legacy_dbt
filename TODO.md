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

---

## Agent-data review — improvement backlog (2026-05-30)

This project is consumed by the `dbtPlaysPokemon` agent as a **retrieval corpus queried via
tool calls** (today through `dbt show --inline`), not just a BI warehouse. Synthesised from
an expert review against the conference knowledge base (Rippling/Bridgewater "expose the
shape, let it query"; MCP-for-data-analysts; Context Engineering). The through-line: **this
is a genuinely strong batch model whose richest assets are invisible to the agent.**

### P0 — unlock the data for the agent

- [ ] **The richest models are never queried by the live agent** — the agent only calls
  `get_exit_paths`, `find_encounter_zone`, `recommend_catch_move`, `find_nearest_mart`. The
  analytical heart — `int_battle_outcomes` (who wins a fight), `opt_recommended_teams`,
  `dash_trainer_counters` — is computed but **dark**. Build one
  `recommend_battle_move(player_species, level, moves[], enemy_species, enemy_level)` macro
  (mirroring `recommend_catch_move`) returning best move + expected turns-to-KO + fight/flee.
  Highest-leverage change.
- [ ] **No live-state JOIN** — strategy models key on `level_cap`/`game_stage`, but the agent
  knows the *actual* party (species, level, HP, moves), badges, money. Adopt the
  **parameterised-macro pattern as the JOIN** (generalise `recommend_catch_move`, the only
  live-param macro today): macros take the agent's real party and join to
  `int_pokemon_stats`/movesets/type-effectiveness on the fly. Keep stage-cap precompute for
  *planning* ("what to catch"), live-param macros for *in-the-moment* ("what move now").
  Pairs with the agent writing `live_party`/`live_run` tables (see agent TODO).
- [ ] **Coverage gaps the agent will hit** — add models for: `int_item_shops` (mart × item ×
  price × earliest_stage) so it can reason about affordability vs `read_money()`;
  `int_progression_gates` (HM/key-item requirements per warp/route) so it knows if a route is
  CUT/SURF-locked; promote move effects to a typed `stg_move_effects` (status/stat-stage/
  multiturn) instead of `LIKE '%sleep%'` on free text in `recommend_catch_move`.
  (2026-06-15: the immediate bug — effect text uses a non-breaking space so the `LIKE` never
  matched — is patched in `recommend_catch_move` via `REPLACE(effect, chr(160), ' ')`; the
  typed `stg_move_effects` model is still the durable fix.)
- [ ] **`int_battle_outcomes` assumes player at the stage level cap** — an under-levelled party
  is told it wins fights it loses. Two-track it: keep the cap table for planning; serve
  in-battle decisions from a live-level macro. Document the cap assumption in the model
  description (the agent reads these).

### P1 — make it a better, extensible agent source

- [ ] **Curated "agent mart" layer** — re-enable `dash_trainer_counters` / `dash_team_builder`
  (`+enabled: false` today) — `dash_trainer_counters` is the best-shaped agent artifact in the
  repo (one row per opponent × counter_rank with move, location, turns-to-KO). Move to a
  `marts/` agent layer, rename off `dash_`, expose via `get_counters(trainer, stage, run)`.
- [ ] **Convert the agent's inline SQL to macros** — the agent free-hands f-string SQL against
  *staging* (`int_map_pathfinding`, `stg_nav_map_tiles`, `int_map_connections`,
  `stg_pkmn_evolutions`; see `dbtPlaysPokemon/docs/inline_sql_audit.md`). Provide
  `get_map_edges`, `get_map_tiles`, `get_map_connections`, `get_pre_evolutions`,
  `get_grass_tiles` macros so the macro set is the **interface contract** and escaping lives here.
- [ ] **Centralise name normalisation** — `UPPER(REPLACE(...))` reconciling seed names ↔
  memory-reader enums is duplicated across models, macros and the agent. One `normalize_name()`
  macro (or a canonical name-mapping seed). This is the load-bearing join between the KB and
  live game state; duplication = silent join misses that make a Pokémon "uncatchable".
- [ ] **DRY the trainer-difficulty logic** — duplicated (with divergent formulas) between
  `opt_team_performance.sql:5-46` and `dash_trainer_counters.sql:35-67`. Extract one
  `classify_trainer_difficulty()` macro or an `int_trainer_difficulty` model — same question
  must give the agent the same answer.
- [ ] **Relax the "intermediate has no tests" rule for agent-critical models** — the 250-500
  line CTE models (`int_battle_outcomes`, `int_pokemon_availability`) ship unguarded. Add cheap
  `not_null` on `battle_score`/`player_victory`, `accepted_range` on scores, and a
  "every `game_stage` yields ≥1 player-victory row" test. A silent regression here ships
  straight to the agent.
- [ ] **Decide the semantic layer + dashboard fate** — `_semantic.yml` (with a synthetic
  `game_data_date`) is built but never called by the agent (it does inline SQL). Either expose
  it via dbt MCP's `query_metrics` as a real curated surface, or delete it + the time-spine to
  cut surface area. Don't leave it half-wired.
- [ ] **Materialisation/access for real-time lookups** — everything is `table`; add filtered
  access macros (`WHERE game_stage=? AND player_pokemon=?`) so point lookups don't scan the
  full battle-outcomes cross-join. (The agent-side fix is a persistent DuckDB connection — see
  agent TODO P0; dbt stays the *build-time* compiler, not the *runtime* query engine.)

### P2 — hygiene

- [ ] **Fix stale/contradictory column docs** — `battle_score` documented "0-1" but actually
  ~−1..1; `stg_moves_from_level_up.type` is a known-bad duplicate column. The agent treats
  descriptions as its documentation, so wrong ranges corrupt its reasoning.
- [ ] **`accepted_values` / `relationships` tests** on agent-facing categoricals (`game_stage`,
  `area`, `warp_type`, `move_origin`) and across the seed↔nav name boundary — a typo'd seed
  value becomes a filter that returns zero rows.
- [ ] **`dbt parse`/`compile` in CI** — `opt_team_performance.sql:299` calls a
  `calculate_tm_usage_recommendation` macro not in the macro listing; confirm every referenced
  macro resolves (latent break for an iterated project).
- [ ] **`find_nearest_mart` ignores its `badge_count` param** and routes through still-locked
  gates — wire it once `int_progression_gates` exists.
- [ ] **Read/write coexistence** — the agent and `dbt build` share one `.db`; open the agent
  connection `read_only=True`, rebuild out-of-band, treat the warehouse as an immutable
  per-session snapshot, and add a startup check that expected tables exist.

### The through-line
1. **Live-state JOIN via parameterised macros** (generalise `recommend_catch_move`).
2. **One curated agent-mart layer** exposed through a handful of generic macros (+ the agent's
   single `query_strategy` tool) — not 30 tables and a dead semantic layer.
3. **Close the 4 coverage gaps** (shop/money, HM/key-item gates, status typing, live-level math).
4. **Add a data-eval safety net** (relax the no-tests rule; `dbt compile` + row-count smoke in
   CI) — see the project-wide eval framework in `dbtPlaysPokemon/docs/eval-framework.md`, esp.
   §6 "does *acting on* the data actually win?" (e.g. promote `assert_team_beats_all_opponents`
   to a gate, add per-gym "recommended team beats Brock" evals).
