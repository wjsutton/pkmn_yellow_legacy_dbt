{% macro get_pre_evolutions(pokemon) %}
-- Catchable pre-evolutions of {{ pokemon }} (walks back up to 2 evolution steps).
-- `pokemon` is expected pre-normalised: UPPER, '-'/'_' replaced with spaces.
SELECT DISTINCT pokemon FROM (
    SELECT UPPER(REPLACE(REPLACE(pokemon, '-', ' '), '_', ' ')) AS pokemon
    FROM {{ ref('stg_pkmn_evolutions') }}
    WHERE UPPER(REPLACE(REPLACE(evolution_name, '-', ' '), '_', ' ')) = '{{ pokemon }}'
    UNION ALL
    SELECT UPPER(REPLACE(REPLACE(e2.pokemon, '-', ' '), '_', ' ')) AS pokemon
    FROM {{ ref('stg_pkmn_evolutions') }} e1
    JOIN {{ ref('stg_pkmn_evolutions') }} e2
        ON UPPER(REPLACE(REPLACE(e1.pokemon, '-', ' '), '_', ' '))
         = UPPER(REPLACE(REPLACE(e2.evolution_name, '-', ' '), '_', ' '))
    WHERE UPPER(REPLACE(REPLACE(e1.evolution_name, '-', ' '), '_', ' ')) = '{{ pokemon }}'
)
{% endmacro %}
