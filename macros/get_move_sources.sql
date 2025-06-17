{% macro get_move_sources() %}
    SELECT 
        pokemon,
        move,
        level,
        'level-up' as move_origin,
        NULL as order,
        NULL as game_stage
    FROM {{ ref('stg_moves_from_level_up') }}

    UNION ALL

    SELECT 
        M.pokemon,
        M.move,
        NULL as level,
        'repurchasible-tm' as move_origin,
        R.order,
        R.next_gym as game_stage
    FROM {{ ref('stg_moves_from_tmhm') }} as M
    INNER JOIN {{ ref('stg_moves_tmhm_locations') }} as L ON M.move = L.move
    INNER JOIN {{ ref('stg_game_route_order') }} as R ON R.map = L.repurchase_route

    UNION ALL

    SELECT 
        M.pokemon,
        M.move,
        NULL as level,
        'single-use-tm' as move_origin,
        R.order,
        R.next_gym as game_stage
    FROM {{ ref('stg_moves_from_tmhm') }} as M
    INNER JOIN {{ ref('stg_moves_tmhm_locations') }} as L ON M.move = L.move
    INNER JOIN {{ ref('stg_game_route_order') }} as R ON R.map = L.earliest_nearest_route
    WHERE L.earliest_nearest_route <> L.repurchase_route
{% endmacro %}