{% macro generate_trainer_run_combinations() %}
    {% set run_configs = [
        {'name': 'Jolteon_Standard_Ledges', 'notes': ['Jolteon Version', 'Legendary'], 'exclude_trainers': []},
        {'name': 'Flareon_Standard_Ledges', 'notes': ['Flareon Version', 'Legendary'], 'exclude_trainers': ['Rival_2']},
        {'name': 'Vaporeon_Standard_Ledges', 'notes': ['Vaporeon Version', 'Legendary'], 'exclude_trainers': ['Rival_1', 'Rival_2']},
        {'name': 'Jolteon_Standard_NoLedges', 'notes': ['Jolteon Version'], 'exclude_trainers': []},
        {'name': 'Flareon_Standard_NoLedges', 'notes': ['Flareon Version'], 'exclude_trainers': ['Rival_2']},
        {'name': 'Vaporeon_Standard_NoLedges', 'notes': ['Vaporeon Version'], 'exclude_trainers': ['Rival_1', 'Rival_2']}
    ] %}
    
    {% for config in run_configs %}
    SELECT 
        '{{ config.name }}' as run,
        trainer,
        game_stage
    FROM all_trainers
    WHERE (notes IN ({{ "'" + config.notes | join("', '") + "'" }}) OR notes IS NULL)
    {% if config.exclude_trainers %}
    AND trainer NOT IN ({{ "'" + config.exclude_trainers | join("', '") + "'" }})
    {% endif %}
    {% if not loop.last %}
    UNION ALL 
    {% endif %}
    {% endfor %}
{% endmacro %}