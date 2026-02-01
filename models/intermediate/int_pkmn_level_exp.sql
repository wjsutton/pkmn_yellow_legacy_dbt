WITH pkmn AS (
    SELECT 
        pokedex,
        pokemon,
        growth_rate,
        base_exp
    FROM {{ ref('int_pkmn_exp_data') }}
),

levels AS (
    SELECT UNNEST(GENERATE_SERIES(1, 100)) AS level
),

pkmn_levels AS (
    SELECT
        p.pokedex,
        p.pokemon,
        p.growth_rate,
        p.base_exp,
        l.level
    FROM pkmn p
    CROSS JOIN levels l
)

SELECT
    pokedex,
    pokemon,
    growth_rate,
    base_exp,
    level,
    
    -- Total EXP to reach this level
    {{ calculate_total_exp_for_level('level', 'growth_rate') }} AS total_exp_at_level,
    
    -- EXP to next level (NULL at level 100)
    CASE 
        WHEN level < 100 THEN {{ calculate_exp_to_next_level('level', 'growth_rate') }}
        ELSE NULL 
    END AS exp_to_next_level,
    
    -- EXP this Pokemon gives when defeated as WILD at this level
    {{ calculate_wild_exp('base_exp', 'level') }} AS wild_exp_yield,
    
    -- EXP this Pokemon gives when defeated by TRAINER at this level
    {{ calculate_trainer_exp('base_exp', 'level') }} AS trainer_exp_yield

FROM pkmn_levels
ORDER BY pokedex, level
