{% macro calculate_performance_tier(score, tier_type='pokemon') %}
    {% if tier_type == 'pokemon' %}
        -- Pokemon performance tier based on route score
        CASE 
            WHEN {{ score }} >= 8.0 THEN 'Elite'
            WHEN {{ score }} >= 6.0 THEN 'Strong' 
            WHEN {{ score }} >= 4.0 THEN 'Solid'
            WHEN {{ score }} >= 2.0 THEN 'Viable'
            ELSE 'Weak'
        END
    {% elif tier_type == 'team' %}
        -- Team quality assessment based on average team score
        CASE 
            WHEN {{ score }} >= 6.0 THEN 'Elite Team'
            WHEN {{ score }} >= 4.5 THEN 'Strong Team'
            WHEN {{ score }} >= 3.0 THEN 'Solid Team'
            ELSE 'Weak Team'
        END
    {% else %}
        -- Generic performance tier with moderate thresholds
        CASE 
            WHEN {{ score }} >= 7.0 THEN 'Elite'
            WHEN {{ score }} >= 5.0 THEN 'Strong' 
            WHEN {{ score }} >= 3.0 THEN 'Solid'
            WHEN {{ score }} >= 1.0 THEN 'Viable'
            ELSE 'Weak'
        END
    {% endif %}
{% endmacro %}