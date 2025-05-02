
{% macro calculate_stat_rby(base_stat, level, dvs=7) %}
    (FLOOR(((({{ base_stat }} + {{ dvs }}) * 2 + 63) * {{ level }}) / 100) + 5)
{% endmacro %}
