{% macro calculate_battle_exp(base_exp, defeated_level, is_trainer, is_traded, participants) %}
(
FLOOR(
    FLOOR({{ base_exp }}::double * {{ defeated_level }}::double / 7.0)
    * CASE WHEN {{ is_trainer }} THEN 1.5 ELSE 1.0 END
    * CASE WHEN {{ is_traded }} THEN 1.5 ELSE 1.0 END
    / GREATEST(1, {{ participants }}::double)
)::integer
)
{% endmacro %}


{% macro calculate_wild_exp(base_exp, defeated_level) %}
(
FLOOR({{ base_exp }}::double * {{ defeated_level }}::double / 7.0)::integer
)
{% endmacro %}


{% macro calculate_trainer_exp(base_exp, defeated_level) %}
(
FLOOR(FLOOR({{ base_exp }}::double * {{ defeated_level }}::double / 7.0) * 1.5)::integer
)
{% endmacro %}
