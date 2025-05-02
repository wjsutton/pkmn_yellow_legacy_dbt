
WITH first_catch AS (

SELECT 
	pokemon,
	MIN(earliest_route) as earliest_route
FROM  {{ ref('int_pkmn_catchable') }} as P
INNER JOIN {{ ref('stg_game_route_order') }} as R on P.earliest_route  <= R."order"
GROUP BY pokemon

)
, base_pokemon as (
SELECT 
	R.map,
	R."order",
	R.next_gym,
	F.pokemon as initial_pokemon,
	L.level_cap,
	F.pokemon
FROM {{ ref('stg_game_route_order') }} as R
INNER JOIN first_catch as F on F.earliest_route <= R."order"
INNER JOIN {{ ref('int_game_level_cap') }} as L on L.game_stage = R.next_gym
) 

,first_evolve_via_level_up AS (

SELECT 
	B.map,
	B."order",
	B.next_gym,
	B.initial_pokemon, 
	B.level_cap,
	E1.evolution_name as pokemon
FROM base_pokemon as B
INNER JOIN {{ ref('stg_pkmn_evolutions') }} as E1 on E1.pokemon = B.pokemon
WHERE E1.evolution_level <= B.level_cap
GROUP BY ALL 

)

,second_evolve_via_level_up AS (

SELECT 
	F.map,
	F."order",
	F.next_gym,
	F.initial_pokemon, 
	F.level_cap,
	E2.evolution_name as pokemon
FROM first_evolve_via_level_up as F
INNER JOIN {{ ref('stg_pkmn_evolutions') }} as E2 on E2.pokemon = F.pokemon
WHERE E2.evolution_level <= F.level_cap
GROUP BY ALL 

)

, all_level_ups as (

SELECT * FROM base_pokemon

	UNION ALL 

SELECT * FROM first_evolve_via_level_up

	UNION ALL 

SELECT * FROM second_evolve_via_level_up

)


, all_pokemon_options as (

	SELECT 
		P.map,
		CASE 
			WHEN P."order" > (SELECT MIN("order") FROM stg_game_route_order WHERE map='Route7')
			THEN P."order"
			ELSE (SELECT MIN("order") FROM stg_game_route_order WHERE map='Route7')
		END as "order",
		CASE 
			WHEN P."order" > (SELECT MIN("order") FROM stg_game_route_order WHERE map='Route7')
			THEN P.next_gym
			ELSE (SELECT next_gym FROM stg_game_route_order WHERE map='Route7')
		END as next_gym,
		P.initial_pokemon, 
		P.level_cap,
		E.evolution_name as pokemon
	FROM all_level_ups as P
	INNER JOIN {{ ref('stg_pkmn_evolutions') }} as E on E.pokemon = P.pokemon
	WHERE E.evolution_stone IN ('Water','Fire','Leaf','Thunder')
    AND E.evolution_name <> 'Raichu'

UNION ALL 

	SELECT 
		P.map,
		CASE 
			WHEN P."order" > (SELECT MIN("order") FROM stg_game_route_order WHERE map='MtMoon1F')
			THEN P."order"
			ELSE (SELECT MIN("order") FROM stg_game_route_order WHERE map='MtMoon1F')
		END as "order",
		CASE 
			WHEN P."order" > (SELECT MIN("order") FROM stg_game_route_order WHERE map='MtMoon1F')
			THEN P.next_gym
			ELSE (SELECT next_gym FROM stg_game_route_order WHERE map='MtMoon1F')
		END as next_gym,
		P.initial_pokemon, 
		P.level_cap,
		E.evolution_name as pokemon
	FROM all_level_ups as P
	INNER JOIN {{ ref('stg_pkmn_evolutions') }} as E on E.pokemon = P.pokemon
	WHERE E.evolution_stone = 'Moon'

UNION ALL

	SELECT * FROM all_level_ups

)

SELECT 
    {{ dbt_utils.generate_surrogate_key(['pokemon','map','"order"','initial_pokemon']) }} as id,
	map,
	"order",
	next_gym,
	initial_pokemon,
	level_cap,
	pokemon
FROM all_pokemon_options 


