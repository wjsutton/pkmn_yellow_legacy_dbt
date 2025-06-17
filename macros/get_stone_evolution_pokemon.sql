{% macro get_stone_evolution_pokemon(base_cte, stones, route_condition) %}
    SELECT 
        P.map,
        CASE 
            WHEN P."order" > (SELECT MIN("order") FROM {{ ref('stg_game_route_order') }} WHERE map='{{ route_condition }}')
            THEN P."order"
            ELSE (SELECT MIN("order") FROM {{ ref('stg_game_route_order') }} WHERE map='{{ route_condition }}')
        END as "order",
        CASE 
            WHEN P."order" > (SELECT MIN("order") FROM {{ ref('stg_game_route_order') }} WHERE map='{{ route_condition }}')
            THEN P.next_gym
            ELSE (SELECT next_gym FROM {{ ref('stg_game_route_order') }} WHERE map='{{ route_condition }}')
        END as next_gym,
        P.initial_pokemon, 
        P.level_cap,
        E.evolution_name as pokemon
    FROM {{ base_cte }} as P
    INNER JOIN {{ ref('stg_pkmn_evolutions') }} as E 
        ON E.pokemon = P.pokemon
    WHERE E.evolution_stone IN ({{ "'" + stones|join("', '") + "'" }})
    {% if route_condition == 'Route7' %}
    AND E.evolution_name <> 'Raichu'
    {% endif %}
{% endmacro %}