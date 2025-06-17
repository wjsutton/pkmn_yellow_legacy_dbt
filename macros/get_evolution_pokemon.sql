{% macro get_evolution_pokemon(base_cte, evolution_level_field, evolution_name_field='evolution_name') %}
    SELECT 
        B.map,
        B."order",
        B.next_gym,
        B.initial_pokemon, 
        B.level_cap,
        E.{{ evolution_name_field }} as pokemon
    FROM {{ base_cte }} as B
    INNER JOIN {{ ref('stg_pkmn_evolutions') }} as E 
        ON E.pokemon = B.pokemon
    WHERE E.{{ evolution_level_field }} <= B.level_cap
    GROUP BY ALL
{% endmacro %}