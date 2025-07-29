WITH level_up_moves AS (
    SELECT 
        M.pokemon,
        M.move,
        M.level,
        'level-up' as move_origin,
        NULL as route_order,
        NULL as game_stage,
        NULL as location_details,
        S.type as move_type,
        S.power as move_power,
        S.acc as move_accuracy,
        S.pp as move_pp,
        S.hits as move_hits,
        S.hits_min as move_hits_min,
        S.hits_max as move_hits_max,
        S.critical_hit_ratio,
        PS.stat_used as move_stat_used
    FROM {{ ref('stg_moves_from_level_up') }} M
    INNER JOIN {{ ref('stg_moves_stats') }} S ON M.move = S.move
    INNER JOIN {{ ref('stg_moves_phys_spec') }} PS ON PS.type = S.type
),

repurchasable_tm_moves AS (
    SELECT 
        M.pokemon,
        M.move,
        NULL as level,
        'repurchasible-tm' as move_origin,
        R.order as route_order,
        R.next_gym as game_stage,
        'Repurchasable at ' || L.repurchase_route as location_details,
        S.type as move_type,
        S.power as move_power,
        S.acc as move_accuracy,
        S.pp as move_pp,
        S.hits as move_hits,
        S.hits_min as move_hits_min,
        S.hits_max as move_hits_max,
        S.critical_hit_ratio,
        PS.stat_used as move_stat_used
    FROM {{ ref('stg_moves_from_tmhm') }} M
    INNER JOIN {{ ref('stg_moves_tmhm_locations') }} L ON M.move = L.move
    INNER JOIN {{ ref('stg_game_route_order') }} R ON R.map = L.repurchase_route
    INNER JOIN {{ ref('stg_moves_stats') }} S ON M.move = S.move
    INNER JOIN {{ ref('stg_moves_phys_spec') }} PS ON PS.type = S.type
),

single_use_tm_moves AS (
    SELECT 
        M.pokemon,
        M.move,
        NULL as level,
        'single-use-tm' as move_origin,
        R.order as route_order,
        R.next_gym as game_stage,
        'Single-use TM at ' || L.earliest_nearest_route as location_details,
        S.type as move_type,
        S.power as move_power,
        S.acc as move_accuracy,
        S.pp as move_pp,
        S.hits as move_hits,
        S.hits_min as move_hits_min,
        S.hits_max as move_hits_max,
        S.critical_hit_ratio,
        PS.stat_used as move_stat_used
    FROM {{ ref('stg_moves_from_tmhm') }} M
    INNER JOIN {{ ref('stg_moves_tmhm_locations') }} L ON M.move = L.move
    INNER JOIN {{ ref('stg_game_route_order') }} R ON R.map = L.earliest_nearest_route
    INNER JOIN {{ ref('stg_moves_stats') }} S ON M.move = S.move
    INNER JOIN {{ ref('stg_moves_phys_spec') }} PS ON PS.type = S.type
    WHERE L.earliest_nearest_route <> L.repurchase_route
),

all_move_sources AS (
    SELECT * FROM level_up_moves
    UNION ALL
    SELECT * FROM repurchasable_tm_moves
    UNION ALL
    SELECT * FROM single_use_tm_moves
)

SELECT 
    {{ dbt_utils.generate_surrogate_key(['pokemon','move','move_origin','COALESCE(level,0)','COALESCE(route_order,0)']) }} as id,
    pokemon,
    move,
    level,
    move_origin,
    route_order,
    game_stage,
    location_details,
    move_type,
    move_power,
    move_accuracy,
    move_pp,
    move_hits,
    move_hits_min,
    move_hits_max,
    critical_hit_ratio,
    move_stat_used,
    -- Add convenience flags
    CASE WHEN move_origin = 'level-up' THEN 1 ELSE 0 END as is_level_up_move,
    CASE WHEN move_origin = 'single-use-tm' THEN 1 ELSE 0 END as is_single_use_tm,
    CASE WHEN move_origin = 'repurchasible-tm' THEN 1 ELSE 0 END as is_repurchasable_tm,
    CASE WHEN move_power = 'N/A' OR move_power IS NULL THEN 0 ELSE 1 END as is_damaging_move,
    -- Add STAB calculation helper (will need pokemon types joined later)
    ROW_NUMBER() OVER(PARTITION BY pokemon, move ORDER BY 
        CASE move_origin 
            WHEN 'level-up' THEN 1 
            WHEN 'repurchasible-tm' THEN 2 
            WHEN 'single-use-tm' THEN 3 
        END,
        level ASC NULLS LAST,
        route_order ASC NULLS LAST
    ) as move_priority_rank
FROM all_move_sources
WHERE move_power <> 'N/A'  -- Exclude non-damaging moves for battle analysis