# dbt Fusion Compatibility Guide

This document tracks the project's readiness for migration to dbt Fusion (dbt 2.0) when DuckDB adapter support becomes available.

## Current Status: Prepared for Fusion

| Component | Status | Notes |
|-----------|--------|-------|
| `require-dbt-version` | Ready | Set to `>=1.8.0,<3.0.0` |
| `dbt_utils` package | Ready | Using Fusion-compatible version range |
| DuckDB adapter | **Blocked** | Not yet supported by Fusion |
| SQL models | Ready | No Python models used |
| Macros | Ready | Standard Jinja macros, no deprecated patterns |

## Blocker: DuckDB Adapter Not Supported

dbt Fusion currently only supports these data platforms:
- Snowflake
- BigQuery
- Databricks
- Redshift

**DuckDB is NOT yet supported.** There is an active feature request:
- [dbt-fusion Issue #110](https://github.com/dbt-labs/dbt-fusion/issues/110) - 138+ reactions
- [dbt-duckdb Issue #559](https://github.com/duckdb/dbt-duckdb/issues/559)

### Why DuckDB Isn't Supported Yet

dbt Fusion's adapters are built on [Apache Arrow DataBase Connectivity (ADBC)](https://arrow.apache.org/adbc/). Adapters require drivers to be signed by dbt Labs for security, limiting support to officially maintained adapters.

## Changes Made for Fusion Compatibility

### 1. dbt_project.yml

Added `require-dbt-version` to signal compatibility with both dbt Core and future Fusion:

```yaml
require-dbt-version: ">=1.8.0,<3.0.0"
```

### 2. packages.yml

Updated `dbt_utils` to use a Fusion-compatible version range:

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: ">=1.3.0,<2.0.0"  # Fusion-compatible
```

## Migration Checklist (When DuckDB Support Arrives)

When dbt Fusion adds DuckDB adapter support, complete these steps:

### Pre-Migration

- [ ] Verify DuckDB adapter is officially supported in Fusion
- [ ] Check for any new deprecated features in your dbt version
- [ ] Run `dbt-autofix` tool to scan for compatibility issues
- [ ] Back up your `data/pkmn_yellow_legacy.db` database

### Installation

- [ ] Install dbt Fusion: `pip install dbt-fusion`
- [ ] Install Fusion DuckDB adapter (command TBD based on release)
- [ ] Update `profiles.yml` if adapter configuration changes

### Testing

- [ ] Run `dbt deps` to install packages
- [ ] Run `dbt debug` to verify connection
- [ ] Run `dbt seed` to test seed loading
- [ ] Run `dbt run` to build all models
- [ ] Run `dbt test` to verify data quality
- [ ] Compare row counts across pipeline layers:
  ```python
  import duckdb
  conn = duckdb.connect('data/pkmn_yellow_legacy.db')
  print('Battle analysis:', conn.execute('SELECT COUNT(*) FROM int_battle_analysis').fetchone()[0])
  print('Optimization:', conn.execute('SELECT COUNT(*) FROM opt_pokemon_performance_by_stage').fetchone()[0])
  ```

### Post-Migration

- [ ] Verify Tableau CSV exports are generated correctly
- [ ] Test dashboard visualizations with new data
- [ ] Document any performance improvements

## Potential Compatibility Concerns

### Macros Using Introspection

These macros use introspection and may need JIT rendering in Fusion:

| Macro | File | Concern Level |
|-------|------|---------------|
| `run_query()` | Various | Low - Fusion handles via JIT |
| `adapter.get_columns_in_relation()` | Macros | Low - Supported in Fusion |

### Custom Macros

This project uses custom macros for Gen 1 Pokemon battle calculations:

| Macro | Status |
|-------|--------|
| `calculate_damage_rby()` | Pure SQL/Jinja - Compatible |
| `calculate_hp_rby()` | Pure SQL/Jinja - Compatible |
| `calculate_stat_rby()` | Pure SQL/Jinja - Compatible |
| `calculate_battle_outcome()` | Pure SQL/Jinja - Compatible |
| `fetch_sprite()` | Pure SQL/Jinja - Compatible |
| `get_move_sources()` | Pure SQL/Jinja - Compatible |

All custom macros use standard Jinja templating and SQL, which are fully supported by Fusion.

## Resources

- [dbt Fusion Documentation](https://docs.getdbt.com/docs/fusion/about-fusion)
- [Upgrading to Fusion Guide](https://docs.getdbt.com/docs/dbt-versions/core-upgrade/upgrading-to-fusion)
- [Fusion Package Compatibility](https://docs.getdbt.com/guides/fusion-package-compat)
- [dbt-duckdb Repository](https://github.com/duckdb/dbt-duckdb)

## Version History

| Date | Change |
|------|--------|
| 2026-01-26 | Initial Fusion compatibility preparation |
