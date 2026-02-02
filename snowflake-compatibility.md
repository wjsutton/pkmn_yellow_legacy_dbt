# Snowflake Compatibility Migration Guide

This document provides step-by-step instructions for migrating the `pkmn_yellow_legacy_map` dbt project from DuckDB to Snowflake. Each step includes the exact file, the current DuckDB-specific code, and the Snowflake-compatible replacement.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Profile & Package Configuration](#2-profile--package-configuration)
3. [Step 1 — Replace `::type` Casting in Macros](#step-1--replace-type-casting-in-macros)
4. [Step 2 — Replace `now()` in Seed Post-Hook](#step-2--replace-now-in-seed-post-hook)
5. [Step 3 — Replace `GENERATE_SERIES` + `UNNEST` in Models](#step-3--replace-generate_series--unnest-in-models)
6. [Step 4 — Replace `QUALIFY` Clauses](#step-4--replace-qualify-clauses)
7. [Step 5 — Replace `UNPIVOT` Syntax](#step-5--replace-unpivot-syntax)
8. [Step 6 — Replace `TRY_CAST`](#step-6--replace-try_cast)
9. [Step 7 — Replace `GROUP BY ALL`](#step-7--replace-group-by-all)
10. [Step 8 — Replace DuckDB Array/List Functions](#step-8--replace-duckdb-arraylist-functions)
11. [Step 9 — Replace `LISTAGG` Syntax](#step-9--replace-listagg-syntax)
12. [Step 10 — Replace `RECURSIVE` CTE Syntax](#step-10--replace-recursive-cte-syntax)
13. [Step 11 — Rewrite `add_dbt_loaded_at_col` Macro for Snowflake DDL](#step-11--rewrite-add_dbt_loaded_at_col-macro-for-snowflake-ddl)
14. [Compatibility Summary Table](#compatibility-summary-table)
15. [Cross-Adapter Strategy (Optional)](#cross-adapter-strategy-optional)

---

## 1. Prerequisites

- Snowflake account with a warehouse, database, and schema configured
- `dbt-snowflake` adapter installed: `pip install dbt-snowflake`
- dbt_utils v1.3.0 is already compatible with Snowflake (no change needed to `packages.yml`)

## 2. Profile & Package Configuration

### `~/.dbt/profiles.yml`

Add a Snowflake target alongside the existing DuckDB config:

```yaml
pkmn_yellow_legacy_map:
  target: snowflake  # Switch default target
  outputs:
    dev:
      type: duckdb
      path: 'data/pkmn_yellow_legacy.db'
      threads: 1
    snowflake:
      type: snowflake
      account: '<your_account>'
      user: '<your_user>'
      password: '<your_password>'  # or use key-pair auth
      role: '<your_role>'
      warehouse: '<your_warehouse>'
      database: '<your_database>'
      schema: 'public'
      threads: 4
```

### `packages.yml`

No changes required. `dbt-labs/dbt_utils v1.3.0` supports Snowflake natively.

### `dbt_project.yml`

No changes required to the project config itself. The schema routing (`staging`, `intermediate`, `optimisation`) works identically in Snowflake.

---

## Step 1 — Replace `::type` Casting in Macros

DuckDB supports PostgreSQL-style `::type` casting. Snowflake requires `CAST(... AS type)`.

> **Pattern**: `value::double` becomes `CAST(value AS DOUBLE)`, `value::integer` becomes `CAST(value AS INTEGER)`.

### 1a. `macros/calculate_damage_rby.sql`

**Current (lines 6, 12, 13, 15, 17):**
```sql
{% macro calculate_damage_rby(defender_stat,defender_hp, attacker_stat, attacker_level, move, acc, move_type_effectiveness, stab, move_power, hits) %}

(
CASE
    WHEN {{ move_power }} = 'N/A' THEN 0
    WHEN {{ move_power }} = 'KO' THEN {{ defender_hp }} * (CASE WHEN {{ acc }}='N/A' THEN 1.0 ELSE {{ acc }}::double END)
    WHEN {{ move }} IN ('Counter', 'Bide', 'Mirror Move') THEN 0
    WHEN {{ move_type_effectiveness }} = 0 THEN 0
    WHEN {{ move }} = 'Sonicboom' THEN 20
    WHEN {{ move }} = 'Dragon Rage' THEN 40
    WHEN {{ move }} = 'Super Fang' THEN (CASE WHEN {{ defender_hp }} > 0 THEN FLOOR({{ defender_hp }} / 2) ELSE 0 END)
    WHEN {{ move }} = 'Psywave' THEN FLOOR(1 + (({{ attacker_level }}::double / 2) / 2))
    WHEN {{ move }} IN ('Seismic Toss', 'Night Shade') THEN {{ attacker_level }}::double
    ELSE
        (FLOOR(((LEAST(997,(FLOOR(FLOOR((2 * FLOOR({{ attacker_level }} / 5) + 2) * GREATEST(1,COALESCE({{ attacker_stat }},1)) * {{ move_power }}::double) / GREATEST(1,COALESCE({{ defender_stat }},1)))) / 50) + 2) * {{ stab }} * {{ move_type_effectiveness }})))
        / (CASE WHEN {{ move }} IN ('Solarbeam','Razor Wind','Skull Bash') THEN 2 ELSE 1 END)
END) * (CASE WHEN {{ move_power }} = 'KO' THEN 1.0 WHEN {{ acc }}='N/A' THEN 1.0 ELSE {{ acc }}::double END)

{% endmacro %}
```

**Replacement:**
```sql
{% macro calculate_damage_rby(defender_stat,defender_hp, attacker_stat, attacker_level, move, acc, move_type_effectiveness, stab, move_power, hits) %}

(
CASE
    WHEN {{ move_power }} = 'N/A' THEN 0
    WHEN {{ move_power }} = 'KO' THEN {{ defender_hp }} * (CASE WHEN {{ acc }}='N/A' THEN 1.0 ELSE CAST({{ acc }} AS DOUBLE) END)
    WHEN {{ move }} IN ('Counter', 'Bide', 'Mirror Move') THEN 0
    WHEN {{ move_type_effectiveness }} = 0 THEN 0
    WHEN {{ move }} = 'Sonicboom' THEN 20
    WHEN {{ move }} = 'Dragon Rage' THEN 40
    WHEN {{ move }} = 'Super Fang' THEN (CASE WHEN {{ defender_hp }} > 0 THEN FLOOR({{ defender_hp }} / 2) ELSE 0 END)
    WHEN {{ move }} = 'Psywave' THEN FLOOR(1 + ((CAST({{ attacker_level }} AS DOUBLE) / 2) / 2))
    WHEN {{ move }} IN ('Seismic Toss', 'Night Shade') THEN CAST({{ attacker_level }} AS DOUBLE)
    ELSE
        (FLOOR(((LEAST(997,(FLOOR(FLOOR((2 * FLOOR({{ attacker_level }} / 5) + 2) * GREATEST(1,COALESCE({{ attacker_stat }},1)) * CAST({{ move_power }} AS DOUBLE)) / GREATEST(1,COALESCE({{ defender_stat }},1)))) / 50) + 2) * {{ stab }} * {{ move_type_effectiveness }})))
        / (CASE WHEN {{ move }} IN ('Solarbeam','Razor Wind','Skull Bash') THEN 2 ELSE 1 END)
END) * (CASE WHEN {{ move_power }} = 'KO' THEN 1.0 WHEN {{ acc }}='N/A' THEN 1.0 ELSE CAST({{ acc }} AS DOUBLE) END)

{% endmacro %}
```

### 1b. `macros/calculate_total_exp_for_level.sql`

**Current:**
```sql
{% macro calculate_total_exp_for_level(level, growth_rate) %}
(
CASE {{ growth_rate }}
    WHEN 'fast' THEN
        FLOOR(0.8 * POWER({{ level }}::double, 3))::integer
    WHEN 'medium_fast' THEN
        POWER({{ level }}::double, 3)::integer
    WHEN 'medium_slow' THEN
        GREATEST(0, FLOOR(1.2 * POWER({{ level }}::double, 3) - 15 * POWER({{ level }}::double, 2) + 100 * {{ level }}::double - 140))::integer
    WHEN 'slow' THEN
        FLOOR(1.25 * POWER({{ level }}::double, 3))::integer
    ELSE 0
END
)
{% endmacro %}
```

**Replacement:**
```sql
{% macro calculate_total_exp_for_level(level, growth_rate) %}
(
CASE {{ growth_rate }}
    WHEN 'fast' THEN
        CAST(FLOOR(0.8 * POWER(CAST({{ level }} AS DOUBLE), 3)) AS INTEGER)
    WHEN 'medium_fast' THEN
        CAST(POWER(CAST({{ level }} AS DOUBLE), 3) AS INTEGER)
    WHEN 'medium_slow' THEN
        CAST(GREATEST(0, FLOOR(1.2 * POWER(CAST({{ level }} AS DOUBLE), 3) - 15 * POWER(CAST({{ level }} AS DOUBLE), 2) + 100 * CAST({{ level }} AS DOUBLE) - 140)) AS INTEGER)
    WHEN 'slow' THEN
        CAST(FLOOR(1.25 * POWER(CAST({{ level }} AS DOUBLE), 3)) AS INTEGER)
    ELSE 0
END
)
{% endmacro %}
```

### 1c. `macros/calculate_exp_to_next_level.sql`

**Current:**
```sql
{% macro calculate_exp_to_next_level(level, growth_rate) %}
(
CASE {{ growth_rate }}
    WHEN 'fast' THEN
        (FLOOR(0.8 * POWER(({{ level }} + 1)::double, 3)) - FLOOR(0.8 * POWER({{ level }}::double, 3)))::integer
    WHEN 'medium_fast' THEN
        (POWER(({{ level }} + 1)::double, 3) - POWER({{ level }}::double, 3))::integer
    WHEN 'medium_slow' THEN
        (GREATEST(0, FLOOR(1.2 * POWER(({{ level }} + 1)::double, 3) - 15 * POWER(({{ level }} + 1)::double, 2) + 100 * ({{ level }} + 1)::double - 140))
        - GREATEST(0, FLOOR(1.2 * POWER({{ level }}::double, 3) - 15 * POWER({{ level }}::double, 2) + 100 * {{ level }}::double - 140)))::integer
    WHEN 'slow' THEN
        (FLOOR(1.25 * POWER(({{ level }} + 1)::double, 3)) - FLOOR(1.25 * POWER({{ level }}::double, 3)))::integer
    ELSE 0
END
)
{% endmacro %}
```

**Replacement:**
```sql
{% macro calculate_exp_to_next_level(level, growth_rate) %}
(
CASE {{ growth_rate }}
    WHEN 'fast' THEN
        CAST(FLOOR(0.8 * POWER(CAST({{ level }} + 1 AS DOUBLE), 3)) - FLOOR(0.8 * POWER(CAST({{ level }} AS DOUBLE), 3)) AS INTEGER)
    WHEN 'medium_fast' THEN
        CAST(POWER(CAST({{ level }} + 1 AS DOUBLE), 3) - POWER(CAST({{ level }} AS DOUBLE), 3) AS INTEGER)
    WHEN 'medium_slow' THEN
        CAST(GREATEST(0, FLOOR(1.2 * POWER(CAST({{ level }} + 1 AS DOUBLE), 3) - 15 * POWER(CAST({{ level }} + 1 AS DOUBLE), 2) + 100 * CAST({{ level }} + 1 AS DOUBLE) - 140))
        - GREATEST(0, FLOOR(1.2 * POWER(CAST({{ level }} AS DOUBLE), 3) - 15 * POWER(CAST({{ level }} AS DOUBLE), 2) + 100 * CAST({{ level }} AS DOUBLE) - 140)) AS INTEGER)
    WHEN 'slow' THEN
        CAST(FLOOR(1.25 * POWER(CAST({{ level }} + 1 AS DOUBLE), 3)) - FLOOR(1.25 * POWER(CAST({{ level }} AS DOUBLE), 3)) AS INTEGER)
    ELSE 0
END
)
{% endmacro %}
```

### 1d. `macros/calculate_battle_exp.sql`

**Current:**
```sql
{% macro calculate_battle_exp(base_exp, defeated_level, is_trainer, is_traded, participants) %}
(
FLOOR(
    FLOOR({{ base_exp }}::double * {{ defeated_level }}::double / 7.0)
    * CASE WHEN {{ is_trainer }} THEN 1.5 ELSE 1.0 END
    * CASE WHEN {{ is_traded }} THEN 1.5 ELSE 1.0 END
    / GREATEST(1, {{ participants }}::double)
)::integer
)
{% endmacro %}


{% macro calculate_wild_exp(base_exp, defeated_level) %}
(
FLOOR({{ base_exp }}::double * {{ defeated_level }}::double / 7.0)::integer
)
{% endmacro %}


{% macro calculate_trainer_exp(base_exp, defeated_level) %}
(
FLOOR(FLOOR({{ base_exp }}::double * {{ defeated_level }}::double / 7.0) * 1.5)::integer
)
{% endmacro %}
```

**Replacement:**
```sql
{% macro calculate_battle_exp(base_exp, defeated_level, is_trainer, is_traded, participants) %}
(
CAST(FLOOR(
    FLOOR(CAST({{ base_exp }} AS DOUBLE) * CAST({{ defeated_level }} AS DOUBLE) / 7.0)
    * CASE WHEN {{ is_trainer }} THEN 1.5 ELSE 1.0 END
    * CASE WHEN {{ is_traded }} THEN 1.5 ELSE 1.0 END
    / GREATEST(1, CAST({{ participants }} AS DOUBLE))
) AS INTEGER)
)
{% endmacro %}


{% macro calculate_wild_exp(base_exp, defeated_level) %}
(
CAST(FLOOR(CAST({{ base_exp }} AS DOUBLE) * CAST({{ defeated_level }} AS DOUBLE) / 7.0) AS INTEGER)
)
{% endmacro %}


{% macro calculate_trainer_exp(base_exp, defeated_level) %}
(
CAST(FLOOR(FLOOR(CAST({{ base_exp }} AS DOUBLE) * CAST({{ defeated_level }} AS DOUBLE) / 7.0) * 1.5) AS INTEGER)
)
{% endmacro %}
```

### 1e. `macros/calculate_crit_multiplier_rby.sql`

**Current:**
```sql
{% macro calculate_crit_multiplier_rby(base_speed, critical_hit_ratio, attacker_level, move, move_power) %}

(
CASE
    WHEN {{ move_power }} = 'KO' THEN 1.0
    WHEN {{ move }} IN ('Sonicboom', 'Dragon Rage', 'Super Fang', 'Psywave', 'Seismic Toss', 'Night Shade') THEN 1.0
    ELSE 1.0 + (
        LEAST(FLOOR({{ base_speed }}::double * {{ critical_hit_ratio }}::double), 255.0) / 256.0
    ) * (
        (2.0 * {{ attacker_level }}::double + 5.0) / ({{ attacker_level }}::double + 5.0) - 1.0
    )
END
)

{% endmacro %}
```

**Replacement:**
```sql
{% macro calculate_crit_multiplier_rby(base_speed, critical_hit_ratio, attacker_level, move, move_power) %}

(
CASE
    WHEN {{ move_power }} = 'KO' THEN 1.0
    WHEN {{ move }} IN ('Sonicboom', 'Dragon Rage', 'Super Fang', 'Psywave', 'Seismic Toss', 'Night Shade') THEN 1.0
    ELSE 1.0 + (
        LEAST(FLOOR(CAST({{ base_speed }} AS DOUBLE) * CAST({{ critical_hit_ratio }} AS DOUBLE)), 255.0) / 256.0
    ) * (
        (2.0 * CAST({{ attacker_level }} AS DOUBLE) + 5.0) / (CAST({{ attacker_level }} AS DOUBLE) + 5.0) - 1.0
    )
END
)

{% endmacro %}
```

### 1f. `macros/calculate_transition_exp.sql`

**Current (line 8):**
```sql
        )::integer
```

**Replacement:**
```sql
{% macro calculate_transition_exp(growth_rate, from_level, to_level, is_traded) %}
(
    CASE WHEN {{ to_level }} > {{ from_level }} THEN
        CAST(FLOOR(
            ({{ calculate_total_exp_for_level(to_level, growth_rate) }}
             - {{ calculate_total_exp_for_level(from_level, growth_rate) }})
            / CASE WHEN {{ is_traded }} = 1 THEN 1.5 ELSE 1.0 END
        ) AS INTEGER)
    ELSE 0
    END
)
{% endmacro %}
```

---

## Step 2 — Replace `now()` in Seed Post-Hook

### `macros/add_dbt_loaded_at_col.sql`

DuckDB uses `now()`. Snowflake uses `CURRENT_TIMESTAMP()`. Additionally, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` is not supported in Snowflake the same way. The macro also uses raw DDL which behaves differently on Snowflake.

**Current:**
```sql
{% macro add_dbt_loaded_at_col() %}
  {% do run_query("ALTER TABLE " ~ this ~ " ADD COLUMN IF NOT EXISTS dbt_loaded_at TIMESTAMP;") %}
  {% do run_query("UPDATE " ~ this ~ " SET dbt_loaded_at = now() WHERE dbt_loaded_at IS NULL;") %}
{% endmacro %}
```

**Replacement:**
```sql
{% macro add_dbt_loaded_at_col() %}
  {% if target.type == 'snowflake' %}
    {% do run_query("ALTER TABLE " ~ this ~ " ADD COLUMN IF NOT EXISTS dbt_loaded_at TIMESTAMP_NTZ;") %}
    {% do run_query("UPDATE " ~ this ~ " SET dbt_loaded_at = CURRENT_TIMESTAMP() WHERE dbt_loaded_at IS NULL;") %}
  {% else %}
    {% do run_query("ALTER TABLE " ~ this ~ " ADD COLUMN IF NOT EXISTS dbt_loaded_at TIMESTAMP;") %}
    {% do run_query("UPDATE " ~ this ~ " SET dbt_loaded_at = now() WHERE dbt_loaded_at IS NULL;") %}
  {% endif %}
{% endmacro %}
```

> **Note**: Using `target.type` dispatching keeps both adapters working from the same codebase. If you only need Snowflake, remove the `else` branch.

---

## Step 3 — Replace `GENERATE_SERIES` + `UNNEST` in Models

DuckDB uses `UNNEST(GENERATE_SERIES(1, N))` to produce row sequences. Snowflake uses `TABLE(GENERATOR(ROWCOUNT => N))` with `ROW_NUMBER()`.

DuckDB also uses `UNNEST(['a', 'b', 'c'])` to expand array literals into rows. Snowflake uses `LATERAL FLATTEN` or manual `UNION ALL` for small static lists.

### 3a. `models/intermediate/int_pokemon_stats.sql` (line 2)

**Current:**
```sql
WITH level_range AS (
    SELECT UNNEST(generate_series(1, 100)) AS pkmn_level
),
```

**Replacement:**
```sql
WITH level_range AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS pkmn_level
    FROM TABLE(GENERATOR(ROWCOUNT => 100))
),
```

### 3b. `models/intermediate/int_level_exp_requirements.sql` (lines 1-7)

**Current:**
```sql
WITH levels AS (
    SELECT UNNEST(GENERATE_SERIES(1, 100)) AS level
),

growth_rates AS (
    SELECT UNNEST(['fast', 'medium_fast', 'medium_slow', 'slow']) AS growth_rate
),
```

**Replacement:**
```sql
WITH levels AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS level
    FROM TABLE(GENERATOR(ROWCOUNT => 100))
),

growth_rates AS (
    SELECT 'fast' AS growth_rate
    UNION ALL SELECT 'medium_fast'
    UNION ALL SELECT 'medium_slow'
    UNION ALL SELECT 'slow'
),
```

### 3c. `models/intermediate/int_pkmn_level_exp.sql` (lines 10-12)

**Current:**
```sql
levels AS (
    SELECT UNNEST(GENERATE_SERIES(1, 100)) AS level
),
```

**Replacement:**
```sql
levels AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS level
    FROM TABLE(GENERATOR(ROWCOUNT => 100))
),
```

---

## Step 4 — Replace `QUALIFY` Clauses

Snowflake **does** support `QUALIFY`, so most of these will work as-is. However, DuckDB allows `QUALIFY` to reference non-window expressions directly, while Snowflake requires the `QUALIFY` clause to contain a window function (or be used after a `WHERE` clause containing one).

**Verdict**: All `QUALIFY` clauses in this project use `ROW_NUMBER() OVER(...)` which is fully supported in Snowflake. **No changes required** for the following files:

- `models/staging/stg_trainers_gym_leaders.sql` (line 41)
- `models/staging/stg_trainers_mandatory.sql` (line 36)
- `models/staging/stg_trainers_non_mandatory.sql` (line 36)
- `models/intermediate/int_stage_pokemon_costs.sql` (line 65)
- `models/intermediate/int_battle_outcomes.sql` (lines 240, 307)

### 4a. `models/intermediate/int_battle_outcomes.sql` — Complex `QUALIFY` (lines 70-81)

This `QUALIFY` has a compound condition mixing non-window and window expressions. Snowflake supports this as long as at least one branch involves a window function. This pattern works in Snowflake.

**Current (lines 70-81):**
```sql
    QUALIFY
        COALESCE(ms.move_power, s.power) = 'KO'
        OR ms.move IN ('Sonicboom', 'Dragon Rage', 'Super Fang', 'Psywave', 'Seismic Toss', 'Night Shade')
        OR ROW_NUMBER() OVER(
            PARTITION BY pa.game_stage, pa.pokemon, COALESCE(ms.move_type, s.type),
                CASE WHEN ms.move_origin = 'single-use-tm' THEN 1 ELSE 0 END
            ORDER BY
                TRY_CAST(COALESCE(ms.move_power, s.power) AS DOUBLE)
                * COALESCE(TRY_CAST(COALESCE(ms.move_accuracy, s.acc) AS DOUBLE), 1.0)
                / (CASE WHEN ms.move IN ('Solarbeam', 'Razor Wind', 'Skull Bash', 'Hyper Beam') THEN 2 ELSE 1 END)
                DESC
        ) = 1
```

**Verdict**: This works in Snowflake as-is. Snowflake's `QUALIFY` supports `OR` between scalar and window expressions. **No changes needed.**

Similarly for lines 128-138 (same pattern). **No changes needed.**

---

## Step 5 — Replace `UNPIVOT` Syntax

### `models/intermediate/int_battle_outcomes.sql` (line 117)

DuckDB's `UNPIVOT` syntax is slightly different from Snowflake's.

**Current:**
```sql
    FROM {{ ref('int_opponent_pokemon') }}
    UNPIVOT (move FOR move_slot IN (move_1, move_2, move_3, move_4)) AS unpvt
```

**Replacement for Snowflake:**
```sql
    FROM {{ ref('int_opponent_pokemon') }}
    UNPIVOT (move FOR move_slot IN (move_1, move_2, move_3, move_4)) AS unpvt
```

**Verdict**: Snowflake supports the same `UNPIVOT` syntax. **No changes needed.**

---

## Step 6 — Replace `TRY_CAST`

### `models/intermediate/int_battle_outcomes.sql` (lines 77-78, 134-135, 270)

DuckDB's `TRY_CAST` returns `NULL` on failure. Snowflake also supports `TRY_CAST` with identical behavior.

**Verdict**: **No changes needed.** `TRY_CAST(x AS DOUBLE)` works on both platforms.

---

## Step 7 — Replace `GROUP BY ALL`

### `models/intermediate/int_opponent_pokemon.sql` (line 91)

DuckDB supports `GROUP BY ALL` as shorthand for grouping by all non-aggregate columns. Snowflake does **not** support this syntax.

**Current:**
```sql
    GROUP BY ALL
```

**Replacement — list all non-aggregate columns explicitly:**
```sql
    GROUP BY
        T.trainer,
        T.game_stage,
        R.game_order,
        T.notes,
        T.pkmn_id,
        S.pokedex,
        T.pokemon,
        T.pkmn_level
```

---

## Step 8 — Replace DuckDB Array/List Functions

This is the highest-effort change. `opt_min_exp_squads.sql` makes heavy use of DuckDB-specific list functions in a recursive CTE.

### 8a. `macros/generate_run_variants.sql` — Array Literals

**Current (lines 12-13, 18-19, 24-25):**
```sql
    ['%_Flareon', '%_Vaporeon']::VARCHAR[] as exclude_rival_patterns,
    []::VARCHAR[] as exclude_trainers
    ...
    ['%_Jolteon', '%_Vaporeon']::VARCHAR[] as exclude_rival_patterns,
    ['Rival_2']::VARCHAR[] as exclude_trainers
    ...
    ['%_Flareon', '%_Jolteon']::VARCHAR[] as exclude_rival_patterns,
    ['Rival_2', 'Rival_1']::VARCHAR[] as exclude_trainers
```

**Replacement:**
```sql
    ARRAY_CONSTRUCT('%_Flareon', '%_Vaporeon') as exclude_rival_patterns,
    ARRAY_CONSTRUCT() as exclude_trainers
    ...
    ARRAY_CONSTRUCT('%_Jolteon', '%_Vaporeon') as exclude_rival_patterns,
    ARRAY_CONSTRUCT('Rival_2') as exclude_trainers
    ...
    ARRAY_CONSTRUCT('%_Flareon', '%_Jolteon') as exclude_rival_patterns,
    ARRAY_CONSTRUCT('Rival_2', 'Rival_1') as exclude_trainers
```

### 8b. `models/optimisation/opt_min_exp_squads.sql` — Array Indexing

**Current (lines 42-44, 55-57):**
```sql
    AND NOT (bv.trainer LIKE rv.exclude_rival_patterns[1])
    AND NOT (bv.trainer LIKE rv.exclude_rival_patterns[2])
    AND NOT list_contains(rv.exclude_trainers, bv.trainer)
```

**Replacement:**
```sql
    AND NOT (bv.trainer LIKE rv.exclude_rival_patterns[0])
    AND NOT (bv.trainer LIKE rv.exclude_rival_patterns[1])
    AND NOT ARRAY_CONTAINS(bv.trainer::VARIANT, rv.exclude_trainers)
```

> **Important**: Snowflake arrays are 0-indexed, DuckDB arrays are 1-indexed. All array index references must shift by -1.

### 8c. `models/optimisation/opt_min_exp_squads.sql` — `list()`, `list_contains()`, `list_filter()`, `list_append()`, `list_distinct()`, `list_concat()`, `len()`

This is the most significant rewrite. The recursive CTE in `opt_min_exp_squads.sql` (lines 62-141) uses DuckDB list manipulation extensively.

**Current `pokemon_opponents` CTE (line 69):**
```sql
        list(DISTINCT trainer_pkmn_id) as beatable_opponents,
```

**Snowflake replacement:**
```sql
        ARRAY_AGG(DISTINCT trainer_pkmn_id) as beatable_opponents,
```

**Current `greedy_team` base case (lines 88, 89, 96):**
```sql
        [pokemon]::VARCHAR[] as team_list,
        beatable_opponents as covered_list
        ...
        total_beatable::FLOAT / GREATEST(1, exp_cost) DESC,
```

**Snowflake replacement:**
```sql
        ARRAY_CONSTRUCT(pokemon) as team_list,
        beatable_opponents as covered_list
        ...
        CAST(total_beatable AS FLOAT) / GREATEST(1, exp_cost) DESC,
```

**Current recursive step (lines 119-138) — This is the hardest part:**
```sql
            len(list_filter(po.beatable_opponents, x -> NOT list_contains(tb.covered_list, x))) as assigned_opponents,
            ...
            list_append(tb.team_list, po.pokemon) as new_team_list,
            list_distinct(list_concat(tb.covered_list, po.beatable_opponents)) as new_covered_list,
            ...
            len(list_filter(po.beatable_opponents, x -> NOT list_contains(tb.covered_list, x)))::FLOAT
                / GREATEST(1, po.exp_cost) DESC,
            len(list_filter(po.beatable_opponents, x -> NOT list_contains(tb.covered_list, x))) DESC,
            ...
            AND NOT list_contains(tb.team_list, po.pokemon)
            ...
            AND len(list_filter(po.beatable_opponents, x -> NOT list_contains(tb.covered_list, x))) > 0
```

**Snowflake does not support lambda functions on arrays.** This recursive CTE must be restructured. The recommended approach is to replace the array-based set operations with a join-based approach:

**Full replacement for the recursive CTE section (lines 80-141):**

```sql
-- Snowflake version: uses string-based team tracking instead of arrays
-- since Snowflake recursive CTEs don't support array lambda operations.
greedy_team AS (
    -- Pick 1: force Pikachu for KeepPikachu runs, else best coverage/cost
    SELECT
        po.game_stage, po.run_name, po.keep_pikachu,
        po.pokemon, po.exp_cost,
        po.total_beatable as assigned_opponents,
        po.total_beatable as total_opponents_beaten,
        1 as pick_order,
        po.pokemon as team_csv,
        -- covered_csv: store as comma-separated trainer_pkmn_ids
        -- (Snowflake recursive CTEs can't use ARRAY_AGG in the anchor)
        po.beatable_csv as covered_csv
    FROM (
        SELECT
            sc.game_stage,
            sc.run_name,
            sc.keep_pikachu,
            sc.pokemon,
            sc.exp_cost,
            COUNT(DISTINCT sc.trainer_pkmn_id) as total_beatable,
            LISTAGG(DISTINCT sc.trainer_pkmn_id, ',') as beatable_csv,
            ROW_NUMBER() OVER (
                PARTITION BY sc.game_stage, sc.run_name
                ORDER BY
                    CASE WHEN sc.keep_pikachu = 1 AND sc.pokemon = 'Pikachu' THEN 0 ELSE 1 END,
                    CAST(COUNT(DISTINCT sc.trainer_pkmn_id) AS FLOAT) / GREATEST(1, sc.exp_cost) DESC,
                    COUNT(DISTINCT sc.trainer_pkmn_id) DESC,
                    sc.exp_cost ASC
            ) as rn
        FROM stage_coverage sc
        GROUP BY sc.game_stage, sc.run_name, sc.keep_pikachu, sc.pokemon, sc.exp_cost
    ) po
    WHERE po.rn = 1

    UNION ALL

    -- Recursive: pick next pokemon covering the most uncovered opponents
    SELECT
        sub.game_stage, sub.run_name, sub.keep_pikachu,
        sub.pokemon, sub.exp_cost,
        sub.assigned_opponents,
        sub.total_opponents_beaten,
        sub.pick_order,
        sub.new_team_csv as team_csv,
        sub.new_covered_csv as covered_csv
    FROM (
        SELECT
            tb.game_stage, tb.run_name, tb.keep_pikachu,
            po.pokemon, po.exp_cost,
            po.new_coverage as assigned_opponents,
            po.total_beatable as total_opponents_beaten,
            tb.pick_order + 1 as pick_order,
            tb.team_csv || ',' || po.pokemon as new_team_csv,
            tb.covered_csv || ',' || po.new_ids_csv as new_covered_csv,
            ROW_NUMBER() OVER (
                PARTITION BY tb.game_stage, tb.run_name
                ORDER BY
                    CAST(po.new_coverage AS FLOAT) / GREATEST(1, po.exp_cost) DESC,
                    po.new_coverage DESC,
                    po.exp_cost ASC
            ) as rn
        FROM greedy_team tb
        INNER JOIN (
            -- For each candidate pokemon, count how many of its beatable opponents
            -- are NOT already in the covered set
            SELECT
                sc.game_stage,
                sc.run_name,
                sc.pokemon,
                sc.exp_cost,
                COUNT(DISTINCT sc.trainer_pkmn_id) as total_beatable,
                COUNT(DISTINCT CASE
                    WHEN NOT CONTAINS(tb2.covered_csv, sc.trainer_pkmn_id)
                    THEN sc.trainer_pkmn_id
                END) as new_coverage,
                LISTAGG(DISTINCT CASE
                    WHEN NOT CONTAINS(tb2.covered_csv, sc.trainer_pkmn_id)
                    THEN sc.trainer_pkmn_id
                END, ',') as new_ids_csv
            FROM stage_coverage sc
            INNER JOIN greedy_team tb2
                ON tb2.game_stage = sc.game_stage AND tb2.run_name = sc.run_name
            WHERE NOT CONTAINS(tb2.team_csv, sc.pokemon)
            GROUP BY sc.game_stage, sc.run_name, sc.pokemon, sc.exp_cost
            HAVING COUNT(DISTINCT CASE
                WHEN NOT CONTAINS(tb2.covered_csv, sc.trainer_pkmn_id)
                THEN sc.trainer_pkmn_id
            END) > 0
        ) po ON po.game_stage = tb.game_stage AND po.run_name = tb.run_name
        WHERE tb.pick_order < 6
    ) sub
    WHERE sub.rn = 1
),
```

> **IMPORTANT NOTE**: The above string-based approach using `CONTAINS` on CSV strings is a simplified approximation. For production use, a more robust approach would be to **replace the recursive CTE entirely with an iterative approach using dbt Jinja loops** (similar to the `greedy_pick_round` macro already in the project). This avoids the recursive CTE limitations entirely.

**Recommended alternative — use the existing `greedy_pick_round` macro pattern:**

The project already has `macros/greedy_pick_round.sql` which implements iterative greedy selection using plain SQL CTEs and `NOT EXISTS` joins. This macro is Snowflake-compatible as-is. Consider restructuring `opt_min_exp_squads.sql` to use 6 rounds of `greedy_pick_round` instead of the recursive CTE.

### 8d. `models/optimisation/opt_min_exp_squads.sql` — Remaining `::` casts

**Current (lines 194, 221-223, 229, 233):**
```sql
        )::integer as exp_earned,
        ...
        THEN ROUND(fp.exp_cost * 1.5)::integer
        ...
        ROUND(ac.opponents_covered::FLOAT / GREATEST(st.total_opponents, 1) * 100, 1) as coverage_pct,
        ...
        (CASE WHEN spc.is_traded = 1 THEN ROUND(fp.exp_cost * 1.5)::integer ELSE fp.exp_cost END)
```

**Replacement:**
```sql
        CAST(... AS INTEGER) as exp_earned,
        ...
        CAST(ROUND(fp.exp_cost * 1.5) AS INTEGER)
        ...
        ROUND(CAST(ac.opponents_covered AS FLOAT) / GREATEST(st.total_opponents, 1) * 100, 1) as coverage_pct,
        ...
        (CASE WHEN spc.is_traded = 1 THEN CAST(ROUND(fp.exp_cost * 1.5) AS INTEGER) ELSE fp.exp_cost END)
```

---

## Step 9 — Replace `LISTAGG` Syntax

### `models/optimisation/opt_team_performance.sql` (line 262)

**Current:**
```sql
        LISTAGG(TA.tm_move, ', ') as allocated_tm_list
```

**Verdict**: Snowflake supports `LISTAGG(column, delimiter)` with identical syntax. **No changes needed.**

---

## Step 10 — Replace `RECURSIVE` CTE Syntax

### `models/optimisation/opt_min_exp_squads.sql` (line 7)

**Current:**
```sql
WITH RECURSIVE run_variants AS (
```

**Verdict**: Snowflake supports `WITH RECURSIVE` — but note that only the recursive CTE itself needs the `RECURSIVE` keyword; non-recursive CTEs in the same `WITH` block don't require it. The current syntax works as-is since `run_variants` is not the recursive CTE. However, in Snowflake `WITH RECURSIVE` is only strictly needed before the actual recursive CTE (`greedy_team`).

**Recommended change**: Move `RECURSIVE` to be directly before `greedy_team`:

**Current structure:**
```sql
WITH RECURSIVE run_variants AS (
    ...
),
greedy_team AS (
    ... UNION ALL ...
)
```

**Replacement:**
```sql
WITH run_variants AS (
    ...
),
...
RECURSIVE greedy_team AS (
    ... UNION ALL ...
)
```

> Note: In Snowflake, `RECURSIVE` must appear immediately after `WITH`, not before an individual CTE. So if the recursive CTE is not the first one, you must keep `WITH RECURSIVE` at the top. **The current syntax actually works as-is in Snowflake.** No change strictly required.

---

## Step 11 — Rewrite `add_dbt_loaded_at_col` Macro for Snowflake DDL

Already covered in [Step 2](#step-2--replace-now-in-seed-post-hook). The `ADD COLUMN IF NOT EXISTS` syntax works in Snowflake.

---

## Compatibility Summary Table

| File | Issue | Snowflake Change Required |
|------|-------|--------------------------|
| `macros/calculate_damage_rby.sql` | `::double` casting (4 locations) | Yes — replace with `CAST(... AS DOUBLE)` |
| `macros/calculate_total_exp_for_level.sql` | `::double`, `::integer` (8 locations) | Yes — replace with `CAST()` |
| `macros/calculate_exp_to_next_level.sql` | `::double`, `::integer` (10 locations) | Yes — replace with `CAST()` |
| `macros/calculate_battle_exp.sql` | `::double`, `::integer` (8 locations) | Yes — replace with `CAST()` |
| `macros/calculate_crit_multiplier_rby.sql` | `::double` (4 locations) | Yes — replace with `CAST()` |
| `macros/calculate_transition_exp.sql` | `::integer` (1 location) | Yes — replace with `CAST()` |
| `macros/add_dbt_loaded_at_col.sql` | `now()` | Yes — use `CURRENT_TIMESTAMP()` |
| `macros/generate_run_variants.sql` | `[]::VARCHAR[]` array literals | Yes — use `ARRAY_CONSTRUCT()` |
| `macros/generate_schema_name.sql` | Standard Jinja | No |
| `macros/calculate_stat_rby.sql` | Standard SQL | No |
| `macros/calculate_hp_rby.sql` | Standard SQL | No |
| `macros/calculate_battle_outcome.sql` | Standard SQL | No |
| `macros/calculate_performance_tier.sql` | Standard SQL (CASE) | No |
| `macros/calculate_tm_efficiency_rating.sql` | Standard SQL (CASE) | No |
| `macros/generate_trainer_run_combinations.sql` | Standard Jinja + SQL | No |
| `macros/greedy_pick_round.sql` | `::FLOAT` (1 location) | Yes — replace with `CAST()` |
| `macros/collapse_evolution_chains.sql` | Standard SQL | No |
| `models/intermediate/int_pokemon_stats.sql` | `UNNEST(generate_series())` | Yes — use `GENERATOR` |
| `models/intermediate/int_level_exp_requirements.sql` | `UNNEST(GENERATE_SERIES())`, `UNNEST([array])` | Yes — use `GENERATOR` + `UNION ALL` |
| `models/intermediate/int_pkmn_level_exp.sql` | `UNNEST(GENERATE_SERIES())` | Yes — use `GENERATOR` |
| `models/intermediate/int_battle_outcomes.sql` | `QUALIFY`, `UNPIVOT`, `TRY_CAST` | No — all supported in Snowflake |
| `models/intermediate/int_stage_pokemon_costs.sql` | `QUALIFY`, `::integer` (2 locations) | Yes — replace `::integer` with `CAST()` |
| `models/intermediate/int_pokemon_movesets.sql` | Standard SQL | No |
| `models/intermediate/int_pokemon_availability.sql` | Standard SQL | No |
| `models/intermediate/int_opponent_pokemon.sql` | `GROUP BY ALL` | Yes — list columns explicitly |
| `models/intermediate/int_pkmn_exp_data.sql` | Uses macros (changes flow through) | No direct changes |
| `models/staging/stg_trainers_gym_leaders.sql` | `QUALIFY` | No — supported in Snowflake |
| `models/staging/stg_trainers_mandatory.sql` | `QUALIFY` | No — supported in Snowflake |
| `models/staging/stg_trainers_non_mandatory.sql` | `QUALIFY` | No — supported in Snowflake |
| `models/staging/stg_trainers_postgame.sql` | Standard SQL | No |
| `models/staging/stg_trainers_legendary.sql` | Standard SQL | No |
| `models/staging/*` (all others) | Standard SQL | No |
| `models/optimisation/opt_team_performance.sql` | `LISTAGG` | No — supported in Snowflake |
| `models/optimisation/opt_recommended_teams.sql` | Uses macros (changes flow through) | No direct changes |
| `models/optimisation/opt_min_exp_squads.sql` | DuckDB list functions, `::` casting, array indexing | **Yes — major rewrite** |

---

## Cross-Adapter Strategy (Optional)

If you want to maintain both DuckDB and Snowflake from the same codebase, use dbt's `dispatch` pattern. Create adapter-specific macro implementations:

### Example: `macros/cross_db/generate_series.sql`

```sql
{% macro generate_integer_series(n) %}
    {{ return(adapter.dispatch('generate_integer_series')(n)) }}
{% endmacro %}

{% macro duckdb__generate_integer_series(n) %}
    SELECT UNNEST(GENERATE_SERIES(1, {{ n }})) AS id
{% endmacro %}

{% macro snowflake__generate_integer_series(n) %}
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS id
    FROM TABLE(GENERATOR(ROWCOUNT => {{ n }}))
{% endmacro %}
```

### Example: `macros/cross_db/safe_cast_double.sql`

```sql
{% macro safe_cast_double(value) %}
    {{ return(adapter.dispatch('safe_cast_double')(value)) }}
{% endmacro %}

{% macro duckdb__safe_cast_double(value) %}
    {{ value }}::double
{% endmacro %}

{% macro snowflake__safe_cast_double(value) %}
    CAST({{ value }} AS DOUBLE)
{% endmacro %}
```

Then update all macros to use `{{ safe_cast_double(attacker_level) }}` instead of `{{ attacker_level }}::double`. This approach adds complexity but lets you run on either adapter without code changes.

---

## Migration Checklist

- [ ] Install `dbt-snowflake` and configure profile
- [ ] Update `macros/calculate_damage_rby.sql` (Step 1a)
- [ ] Update `macros/calculate_total_exp_for_level.sql` (Step 1b)
- [ ] Update `macros/calculate_exp_to_next_level.sql` (Step 1c)
- [ ] Update `macros/calculate_battle_exp.sql` (Step 1d)
- [ ] Update `macros/calculate_crit_multiplier_rby.sql` (Step 1e)
- [ ] Update `macros/calculate_transition_exp.sql` (Step 1f)
- [ ] Update `macros/add_dbt_loaded_at_col.sql` (Step 2)
- [ ] Update `models/intermediate/int_pokemon_stats.sql` (Step 3a)
- [ ] Update `models/intermediate/int_level_exp_requirements.sql` (Step 3b)
- [ ] Update `models/intermediate/int_pkmn_level_exp.sql` (Step 3c)
- [ ] Update `models/intermediate/int_opponent_pokemon.sql` (Step 7)
- [ ] Update `macros/generate_run_variants.sql` (Step 8a)
- [ ] Update `models/optimisation/opt_min_exp_squads.sql` (Steps 8b-8d) — **largest change**
- [ ] Update `macros/greedy_pick_round.sql` — replace `::FLOAT` with `CAST(... AS FLOAT)`
- [ ] Update `models/intermediate/int_stage_pokemon_costs.sql` — replace `::integer` with `CAST(... AS INTEGER)`
- [ ] Run `dbt seed` to load seed data into Snowflake
- [ ] Run `dbt compile` to validate all SQL compiles
- [ ] Run `dbt run` to build all models
- [ ] Run `dbt test` to verify data quality
- [ ] Compare row counts between DuckDB and Snowflake outputs
