{% macro calculate_damage_rby(defender_stat,defender_hp, attacker_stat, attacker_level, move, acc, move_type_effectiveness, stab, move_power, hits) %}


(CASE 
WHEN {{ move_power }} = 'N/A' THEN 0
WHEN {{ move_power }} = 'KO' THEN {{ defender_hp }} * (CASE WHEN {{ acc }}='N/A' THEN 1.0 ELSE {{ acc }}::double END)
WHEN {{ move }} IN ('Counter', 'Bide', 'Mirror Move') THEN 0 
WHEN {{ move_type_effectiveness }} = 0 THEN 0 
WHEN {{ move }} = 'Sonicboom' THEN 20
WHEN {{ move }} = 'Dragon Rage' THEN 40
WHEN {{ move }} = 'Super Fang' THEN FLOOR({{ defender_hp }} / 2)
WHEN {{ move }} = 'Psywave' THEN FLOOR(1 + (({{ attacker_level }}::double / 2) / 2))
WHEN {{ move }} IN ('Seismic Toss', 'Night Shade') THEN {{ attacker_level }}::double
ELSE 
(FLOOR(((LEAST(997,(FLOOR(FLOOR((2 * FLOOR({{ attacker_level }} / 5) + 2) * GREATEST(1, {{ attacker_stat }}) * {{ move_power }}::double) / GREATEST(1, {{ defender_stat }}))) / 50) + 2) * {{ stab }} * {{ move_type_effectiveness }}) / 2))
/ (CASE WHEN {{ move }} IN ('Solarbeam','Razor Wind','Skull Bash','Hyper Beam') THEN 2 ELSE 1 END)
END) * (CASE WHEN {{ move_power }} = 'KO' THEN 1.0 WHEN {{ acc }}='N/A' THEN 1.0 ELSE {{ acc }}::double END)

{% endmacro %}