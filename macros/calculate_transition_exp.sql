{% macro calculate_transition_exp(growth_rate, from_level, to_level, is_traded) %}
(
    CASE WHEN {{ to_level }} > {{ from_level }} THEN
        FLOOR(
            ({{ calculate_total_exp_for_level(to_level, growth_rate) }}
             - {{ calculate_total_exp_for_level(from_level, growth_rate) }})
            / CASE WHEN {{ is_traded }} = 1 THEN 1.5 ELSE 1.0 END
        )::integer
    ELSE 0
    END
)
{% endmacro %}
