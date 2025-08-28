{% macro add_dbt_loaded_at_col() %}
  {% do run_query("ALTER TABLE " ~ this ~ " ADD COLUMN IF NOT EXISTS dbt_loaded_at TIMESTAMP;") %}
  {% do run_query("UPDATE " ~ this ~ " SET dbt_loaded_at = CURRENT_TIMESTAMP() WHERE dbt_loaded_at IS NULL;") %}
{% endmacro %}
