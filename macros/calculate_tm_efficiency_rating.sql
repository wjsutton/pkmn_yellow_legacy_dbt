{% macro calculate_tm_efficiency_rating(tm_count, rating_type='pokemon') %}
    {% if rating_type == 'pokemon' %}
        -- Pokemon TM efficiency based on individual TM usage
        CASE 
            WHEN {{ tm_count }} = 0 THEN 'TM-Free'
            WHEN {{ tm_count }} <= 2 THEN 'TM-Efficient'
            WHEN {{ tm_count }} <= 4 THEN 'TM-Dependent' 
            ELSE 'TM-Heavy'
        END
    {% elif rating_type == 'allocation' %}
        -- TM allocation efficiency (for opt_tm_allocation_final)
        CASE 
            WHEN {{ tm_count }} = 0 THEN 'TM-Free'
            WHEN {{ tm_count }} = 1 THEN 'TM-Efficient'
            WHEN {{ tm_count }} <= 2 THEN 'TM-Moderate'
            ELSE 'TM-Heavy'
        END
    {% elif rating_type == 'team' %}
        -- Team TM investment level
        CASE 
            WHEN {{ tm_count }} = 0 THEN 'TM-Free Team'
            WHEN {{ tm_count }} <= 3 THEN 'Low TM Investment'
            WHEN {{ tm_count }} <= 6 THEN 'Moderate TM Investment'
            ELSE 'High TM Investment'
        END
    {% else %}
        -- Generic TM efficiency rating
        CASE 
            WHEN {{ tm_count }} = 0 THEN 'TM-Free'
            WHEN {{ tm_count }} <= 1 THEN 'TM-Efficient'
            WHEN {{ tm_count }} <= 3 THEN 'TM-Moderate'
            ELSE 'TM-Heavy'
        END
    {% endif %}
{% endmacro %}

{% macro calculate_tm_usage_recommendation(tm_count) %}
    -- Generate usage recommendation based on TM allocation count
    CASE 
        WHEN {{ tm_count }} = 0 THEN 'No TM investment required'
        WHEN {{ tm_count }} = 1 THEN 'Single TM investment - efficient'
        WHEN {{ tm_count }} <= 2 THEN 'Moderate TM investment'
        ELSE 'High TM investment - consider alternatives'
    END
{% endmacro %}