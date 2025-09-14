
SELECT
    P.game_order,
    P.pokemon,
    P.level_cap,
    move,
    pkmn_level,
    move_origin,
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
FROM {{ ref('int_pkmn_available') }} as P
INNER JOIN {{ ref('int_pkmn_movesets') }} as M 
    ON P.pokemon = M.pokemon
    AND (
        (P.level_cap >= M.pkmn_level)
        OR (P.game_order >= M.game_order)
    )