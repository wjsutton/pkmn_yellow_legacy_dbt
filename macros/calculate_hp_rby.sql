
{% macro calculate_hp_rby(base_hp, level, dvs=7) %}
    (FLOOR(((({{ base_hp }} + {{ dvs }}) * 2 + 63) * {{ level }}) / 100) + {{ level }} + 10)
{% endmacro %}

