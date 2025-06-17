{% macro get_trainer_moves(source_table, trainer_filter=none, move_limit=4) %}
    SELECT 
        trainer,
        {% if source_table == 'stg_trainers_gym_leaders' %}
        1 as is_gym_leader,
        {% else %}
        0 as is_gym_leader,
        {% endif %}
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        {% if trainer_filter %}
        '{{ trainer_filter }}' as notes,
        {% else %}
        notes,
        {% endif %}
        level,
        move,
        {% if source_table == 'stg_trainers_legendary' %}
        move_number
        {% else %}
        ROW_NUMBER() OVER (PARTITION BY pkmn_id ORDER BY move) AS move_number
        {% endif %}
    FROM {{ ref(source_table) }}
    {% if move_limit %}
    QUALIFY ROW_NUMBER() OVER(PARTITION BY pkmn_id ORDER BY move) <= {{ move_limit }}
    {% endif %}
{% endmacro %}