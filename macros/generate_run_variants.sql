{% macro generate_run_variants(base_table) %}
    -- Generate all run variants from base stages
    WITH base_runs AS (
        SELECT DISTINCT 
            game_stage,
            CASE 
                WHEN game_stage LIKE '%Badge%' THEN 
                    REGEXP_REPLACE(game_stage, '.*_([^_]+)_[^_]+$', '\1') || '_Standard_Ledges'
                ELSE 'Standard_Ledges'
            END as base_run
        FROM {{ base_table }}
    )
    
    SELECT 
        game_stage,
        base_run,
        base_run as run_name,
        0 as keep_pikachu,
        0 as no_legends
    FROM base_runs
    
    UNION ALL
    
    SELECT 
        game_stage,
        base_run,
        REPLACE(base_run, '_Ledges', '_NoLedges') as run_name,
        0 as keep_pikachu,
        1 as no_legends
    FROM base_runs
    
    UNION ALL
    
    SELECT 
        game_stage,
        base_run,
        base_run || '_keepPikachu' as run_name,
        1 as keep_pikachu,
        0 as no_legends
    FROM base_runs
    
    UNION ALL
    
    SELECT 
        game_stage,
        base_run,
        REPLACE(base_run, '_Ledges', '_NoLedges') || '_keepPikachu' as run_name,  
        1 as keep_pikachu,
        1 as no_legends
    FROM base_runs
{% endmacro %}

{% macro generate_variant_description(keep_pikachu, no_legends) %}
    -- Generate variant description text
    CASE 
        WHEN {{ keep_pikachu }} = 1 AND {{ no_legends }} = 1 THEN 'Pikachu + No Legendaries'
        WHEN {{ keep_pikachu }} = 1 THEN 'Pikachu Included'
        WHEN {{ no_legends }} = 1 THEN 'No Legendaries'
        ELSE 'Standard Run'
    END
{% endmacro %}