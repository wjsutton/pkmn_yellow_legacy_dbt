WITH level_up_moves AS (
    SELECT 
        M.pokemon,
        M.move,
        M.pkmn_level,
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
        NULL as pkmn_level,
        'repurchasible-tm' as move_origin,
        R.game_order as route_order,
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
        NULL as pkmn_level,
        'single-use-tm' as move_origin,
        R.game_order as route_order,
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
    {{ dbt_utils.generate_surrogate_key(['pokemon','move','move_origin','COALESCE(pkmn_level,0)','COALESCE(route_order,0)']) }} as id,
    pokemon,
    move,
    pkmn_level,
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
    move_stat_used
FROM all_move_sources
WHERE move_power <> 'N/A'  