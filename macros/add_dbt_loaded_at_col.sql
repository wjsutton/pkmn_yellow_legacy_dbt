{% macro drop_dbt_loaded_at_col() %}
  {% if execute %}
    {% for node in graph.nodes.values() %}
      {% if node.resource_type == 'seed' %}
        {% set relation = api.Relation.create(
            database=node.database,
            schema=node.schema,
            identifier=node.alias
        ) %}
        {% if adapter.get_relation(database=node.database, schema=node.schema, identifier=node.alias) %}
          {% do run_query("ALTER TABLE " ~ relation ~ " DROP COLUMN IF EXISTS dbt_loaded_at;") %}
        {% endif %}
      {% endif %}
    {% endfor %}
  {% endif %}
{% endmacro %}

{% macro add_dbt_loaded_at_col() %}
  {% if execute %}
    {% for result in results %}
      {% if result.node.resource_type == 'seed' and result.status == 'success' %}
        {% set relation = api.Relation.create(
            database=result.node.database,
            schema=result.node.schema,
            identifier=result.node.alias
        ) %}
        {% do run_query("ALTER TABLE " ~ relation ~ " ADD COLUMN IF NOT EXISTS dbt_loaded_at TIMESTAMP;") %}
        {% do run_query("UPDATE " ~ relation ~ " SET dbt_loaded_at = now() WHERE dbt_loaded_at IS NULL;") %}
      {% endif %}
    {% endfor %}
  {% endif %}
{% endmacro %}
