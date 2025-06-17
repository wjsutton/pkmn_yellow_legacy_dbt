{% macro difficulty_priority() %}
  case 
    when trainer_difficulty = 'Very Hard' then 5
    when trainer_difficulty = 'Hard' then 4
    when trainer_difficulty = 'Medium' then 3
    when trainer_difficulty = 'Requires Specific Counter' then 4
    else 1
  end
{% endmacro %}