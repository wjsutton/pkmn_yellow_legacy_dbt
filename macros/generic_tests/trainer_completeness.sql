{% test trainer_completeness(model) %}
    SELECT DISTINCT
        t.trainer
    FROM {{ ref('int_trainers_all') }} AS t
    WHERE t.trainer <> 'Player'
    EXCEPT
    SELECT DISTINCT
        M.trainer
    FROM {{ model }} as M
    WHERE M.trainer <> 'Player'
{% endtest %}