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
