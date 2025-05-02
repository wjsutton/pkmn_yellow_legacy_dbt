-- Only consider TMs when at their repurchase_route

WITH possible_moves as (
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
INNER JOIN {{ ref('stg_moves_tmhm_locations') }} as L on M.move = L.move
INNER JOIN {{ ref('stg_game_route_order') }} as R on R.map = L.repurchase_route

UNION ALL

SELECT 
    M.pokemon,
    M.move,
    NULL as level,
    'single-use-tm' as move_origin,
    R.order,
    R.next_gym as game_stage
FROM {{ ref('stg_moves_from_tmhm') }} as M
INNER JOIN {{ ref('stg_moves_tmhm_locations') }} as L on M.move = L.move
INNER JOIN {{ ref('stg_game_route_order') }} as R on R.map = L.earliest_nearest_route
WHERE L.earliest_nearest_route <> L.repurchase_route
)

, all_pkmn as (
SELECT 
	'Player' as trainer,
    T.next_gym,
    T.order,
    'Player_' || T.pokemon ||'_1' as pkmn_id,
    T.pokemon,
    MAX(T.level_cap) as level,
    M.move_origin,
    M.move
FROM {{ ref('int_pkmn_team_options') }} as T 
INNER JOIN possible_moves as M on T.pokemon = M.pokemon
WHERE ((M.level <= T.level_cap AND M.order IS NULL)
OR (M.order <= T.order AND M.level IS NULL))
AND M.move NOT IN ('Horn Drill','Fissure','Guillotine','Explosion','Selfdestruct')
GROUP BY ALL

	UNION 

SELECT 
	trainer,
	game_stage as next_gym,
	"order",
	pkmn_id,
	pokemon,
	"level",
    'trainer' as move_origin,
	move
FROM {{ ref('int_trainers_all') }} as t
UNPIVOT(move FOR move_slot IN (move_1, move_2, move_3, move_4)) AS unpvt

)

SELECT 
    CASE WHEN T.trainer = 'Player' THEN 1 ELSE 0 END as player,
	T.trainer,
    T.next_gym,
    T.order,
    T.pkmn_id,
    T.pokemon,
    T.level,
    P.type1,
    P.type2,
    T.move,
    T.move_origin,
    S.type as move_type,
    CASE 
    	WHEN S.type = P.type1 THEN 1.5
    	WHEN S.type = P.type2 THEN 1.5
    	ELSE 1
    END as move_stab,
    PS.stat_used as move_stat,
    S.power as move_power,
    S.acc as move_acc,
    S.hits_min as move_hits_min,
    S.critical_hit_ratio as critical_hit_ratio,
    {{ calculate_hp_rby('P.hp','T.level','7') }} as hp,
    {{ calculate_stat_rby('P.attack','T.level','7') }} as attack,
    {{ calculate_stat_rby('P.defense','T.level','7') }} as defense,
    {{ calculate_stat_rby('P.special','T.level','7') }} as special,
    {{ calculate_stat_rby('P.speed','T.level','7') }} as speed
FROM all_pkmn as T
INNER JOIN {{ ref('stg_moves_stats') }} as S on T.move = S.move
INNER JOIN {{ ref('stg_pkmn_stats') }} as P on P.pokemon = T.pokemon
INNER JOIN {{ ref('stg_moves_phys_spec') }} as PS on PS.type = S.type
WHERE S.power <> 'N/A'
