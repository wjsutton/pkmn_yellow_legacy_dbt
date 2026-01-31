{% macro calculate_crit_multiplier_rby(base_speed, critical_hit_ratio, attacker_level, move, move_power) %}

(
CASE
    WHEN {{ move_power }} = 'KO' THEN 1.0
    WHEN {{ move }} IN ('Sonicboom', 'Dragon Rage', 'Super Fang', 'Psywave', 'Seismic Toss', 'Night Shade') THEN 1.0
    ELSE 1.0 + (
        LEAST(FLOOR({{ base_speed }}::double * {{ critical_hit_ratio }}::double), 255.0) / 256.0
    ) * (
        (2.0 * {{ attacker_level }}::double + 5.0) / ({{ attacker_level }}::double + 5.0) - 1.0
    )
END
)

{% endmacro %}
