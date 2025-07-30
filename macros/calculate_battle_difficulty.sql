{% macro calculate_battle_difficulty(battle_score) %}
    -- Assess battle difficulty based on battle score
    CASE 
        WHEN {{ battle_score }} >= 0.8 THEN 'Easy Win'
        WHEN {{ battle_score }} >= 0.6 THEN 'Favorable'
        WHEN {{ battle_score }} >= 0.4 THEN 'Challenging'
        ELSE 'Very Difficult'
    END
{% endmacro %}

{% macro calculate_move_category(is_assigned_move, single_use_tm) %}
    -- Categorize move based on assignment and TM status
    CASE 
        WHEN {{ is_assigned_move }} = 1 THEN 'ASSIGNED MOVE'
        WHEN {{ single_use_tm }} = 1 THEN 'ALTERNATIVE TM OPTION'
        ELSE 'NATURAL MOVE'
    END
{% endmacro %}