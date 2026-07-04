{% macro check_orphan_relations() %}
{#
    Fails if the warehouse contains tables/views that are not in the current
    dbt manifest (models + seeds). Guards against stale schemas silently
    masking renamed/deleted models (issue #15).

    Usage: dbt run-operation check_orphan_relations
#}
    {% set expected = [] %}
    {% for node in graph.nodes.values() if node.resource_type in ('model', 'seed') %}
        {% do expected.append((node.schema ~ '.' ~ (node.alias or node.name)) | lower) %}
    {% endfor %}

    {% set actual = run_query(
        "select lower(table_schema) || '.' || lower(table_name) as rel
         from information_schema.tables
         where table_schema not in ('information_schema', 'pg_catalog', 'dbt_test__audit')"
    ) %}

    {% set orphans = [] %}
    {% for row in actual.rows %}
        {% if row['rel'] not in expected %}
            {% do orphans.append(row['rel']) %}
        {% endif %}
    {% endfor %}

    {% if orphans %}
        {{ exceptions.raise_compiler_error(
            'Found ' ~ orphans | length ~ ' orphan relation(s) not in the manifest — rebuild the database cleanly (data/create_database.py -> dbt seed -> dbt build): '
            ~ orphans | join(', ')
        ) }}
    {% else %}
        {{ log('check_orphan_relations: OK — all warehouse relations match the manifest (' ~ expected | length ~ ' expected).', info=true) }}
    {% endif %}
{% endmacro %}
