{% macro generate_run_variants(base_table) %}
    -- Generate all 12 run variants (3 rival types × 2 pikachu variants × 2 legendary variants)
    WITH base_stages AS (
        SELECT DISTINCT game_stage
        FROM {{ base_table }}
    ),
    
    rival_variants AS (
        SELECT 
            'Jolteon' as rival_type,
            -- Jolteon run: exclude rival battles ending in '_Flareon' or '_Vaporeon'
            ['%_Flareon', '%_Vaporeon']::VARCHAR[] as exclude_rival_patterns,
            []::VARCHAR[] as exclude_trainers
        UNION ALL
        SELECT 
            'Flareon' as rival_type,
            -- Flareon run: exclude rival battles ending in '_Jolteon' or '_Vaporeon' AND exclude trainer 'Rival_2'
            ['%_Jolteon', '%_Vaporeon']::VARCHAR[] as exclude_rival_patterns,
            ['Rival_2']::VARCHAR[] as exclude_trainers
        UNION ALL
        SELECT 
            'Vaporeon' as rival_type,
            -- Vaporeon run: exclude rival battles ending in '_Flareon' or '_Jolteon' AND exclude trainers 'Rival_2' and 'Rival_1'
            ['%_Flareon', '%_Jolteon']::VARCHAR[] as exclude_rival_patterns,
            ['Rival_2', 'Rival_1']::VARCHAR[] as exclude_trainers
    ),
    
    pikachu_variants AS (
        SELECT 'NoPikachu' as pikachu_variant, 0 as keep_pikachu
        UNION ALL
        SELECT 'KeepPikachu' as pikachu_variant, 1 as keep_pikachu
    ),
    
    legendary_variants AS (
        SELECT 'Ledges' as legendary_variant, 0 as no_legends
        UNION ALL
        SELECT 'NoLedges' as legendary_variant, 1 as no_legends
    )
    
    SELECT 
        BS.game_stage,
        RV.rival_type,
        PV.pikachu_variant,
        LV.legendary_variant,
        -- Run name format: Rival_Pikachu_Legendary
        RV.rival_type || '_' || PV.pikachu_variant || '_' || LV.legendary_variant as run_name,
        PV.keep_pikachu,
        LV.no_legends,
        RV.exclude_rival_patterns,
        RV.exclude_trainers
    FROM base_stages BS
    CROSS JOIN rival_variants RV
    CROSS JOIN pikachu_variants PV
    CROSS JOIN legendary_variants LV
{% endmacro %}

{% macro generate_variant_description(rival_type, keep_pikachu, no_legends) %}
    -- Generate variant description text based on run parameters
    CASE 
        WHEN {{ keep_pikachu }} = 1 AND {{ no_legends }} = 1 THEN {{ rival_type }} || ' + Pikachu + No Legendaries'
        WHEN {{ keep_pikachu }} = 1 AND {{ no_legends }} = 0 THEN {{ rival_type }} || ' + Pikachu + Legendaries'
        WHEN {{ keep_pikachu }} = 0 AND {{ no_legends }} = 1 THEN {{ rival_type }} || ' + No Legendaries'
        ELSE {{ rival_type }} || ' + Legendaries'
    END
{% endmacro %}