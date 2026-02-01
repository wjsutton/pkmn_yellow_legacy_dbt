WITH levels AS (
    SELECT UNNEST(GENERATE_SERIES(1, 100)) AS level
),

growth_rates AS (
    SELECT UNNEST(['fast', 'medium_fast', 'medium_slow', 'slow']) AS growth_rate
),

level_growth_combinations AS (
    SELECT 
        l.level,
        g.growth_rate
    FROM levels l
    CROSS JOIN growth_rates g
)

SELECT
    level,
    growth_rate,
    {{ calculate_total_exp_for_level('level', 'growth_rate') }} AS total_exp_required,
    CASE 
        WHEN level < 100 THEN {{ calculate_exp_to_next_level('level', 'growth_rate') }}
        ELSE NULL 
    END AS exp_to_next_level
FROM level_growth_combinations
ORDER BY growth_rate, level
