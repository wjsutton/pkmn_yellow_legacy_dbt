{% macro calculate_difficulty_penalty(battle_score, difficulty_rating) %}
    -- Calculate difficulty threshold based on rating
    CASE 
        WHEN {{ difficulty_rating }} = 'Easy' THEN 0.3
        WHEN {{ difficulty_rating }} = 'Requires Specific Counter' THEN 0.6
        WHEN {{ difficulty_rating }} = 'Medium' THEN 0.7
        WHEN {{ difficulty_rating }} = 'Hard' THEN 0.8
        WHEN {{ difficulty_rating }} = 'Very Hard' THEN 0.9
        ELSE 0.5  -- Default for missing ratings
    END
{% endmacro %}

{% macro calculate_threshold_penalty(battle_score, difficulty_rating) %}
    -- Calculate penalty if battle score is below difficulty threshold
    GREATEST(0, 
        {{ calculate_difficulty_penalty(battle_score, difficulty_rating) }} - {{ battle_score }}
    )
{% endmacro %}