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
