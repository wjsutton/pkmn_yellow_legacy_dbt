{% macro fetch_sprite(name, type='pokemon', face='front') %}
    (
        '{{ var("sprite_base_url") }}'
        || '/' || '{{ type }}'
        || '/' || '{{ face }}'
        || '/' || lower('{{ name }}')
        || '.png'
    )
{% endmacro %}

