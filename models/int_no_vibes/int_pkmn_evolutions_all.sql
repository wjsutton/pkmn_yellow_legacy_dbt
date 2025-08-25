WITH base_evolutions AS (
    SELECT 
        pokedex,
        pokemon,
        evolution_level,
        evolution_stone,
        evolution_name
    FROM {{ ref('stg_pkmn_evolutions') }}
),

stone_locations AS (
    SELECT 'Fire' as stone_name, 'Route7' as earliest_route
    UNION ALL
    SELECT 'Water', 'Route7'
    UNION ALL  
    SELECT 'Thunder', 'Route7'
    UNION ALL
    SELECT 'Leaf', 'Route7'
    UNION ALL
    SELECT 'Moon', 'MtMoon1F'
),
-- Stone evolution locations and route availability - now pulls actual route orders dynamically
stone_evolution_routes AS (
    SELECT 
        stone_name,
        earliest_route,
        R.game_order as route_order
    FROM stone_locations
    INNER JOIN {{ ref('stg_game_route_order') }} R ON R.map = stone_locations.earliest_route
),

-- Add route availability for stone evolutions
stone_evolutions_with_routes AS (
    SELECT 
        E.*,
        SER.earliest_route,
        SER.route_order,
        R.next_gym as earliest_game_stage
    FROM base_evolutions E
    INNER JOIN stone_evolution_routes SER ON E.evolution_stone = SER.stone_name
    INNER JOIN {{ ref('stg_game_route_order') }} R ON R.map = SER.earliest_route
    WHERE E.evolution_stone IS NOT NULL
),

-- Level evolutions (available when pokemon reaches required level)
level_evolutions AS (
    SELECT 
        E.*,
        NULL as earliest_route,
        NULL as route_order,
        NULL as earliest_game_stage
    FROM base_evolutions E
    WHERE E.evolution_level IS NOT NULL
),

-- Combine all evolution types
all_evolutions AS (
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['pokemon','evolution_name']) }} as id,
        pokemon,
        evolution_name,
        evolution_level,
        evolution_stone,
        earliest_route,
        route_order,
        earliest_game_stage,
        CASE 
            WHEN evolution_level IS NOT NULL THEN 'Level'
            WHEN evolution_stone IS NOT NULL THEN 'Stone'
            ELSE 'Unknown'
        END as evolution_type,
        -- Add evolution stage classification
        1 as evolution_stage
    FROM level_evolutions
    
    UNION ALL
    
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['pokemon','evolution_name']) }} as id,
        pokemon,
        evolution_name,
        evolution_level,
        evolution_stone,
        earliest_route,
        route_order,
        earliest_game_stage,
        'Stone' as evolution_type,
        1 as evolution_stage
    FROM stone_evolutions_with_routes
),

-- Find second-stage evolutions (pokemon that can evolve further)
second_stage_evolutions AS (
    SELECT 
        E1.pokemon,
        E1.evolution_name as first_evolution_name,
        E2.evolution_name as second_evolution_name,
        E1.evolution_level as first_evolution_level,
        E1.evolution_stone as first_evolution_stone,
        E2.evolution_level as second_evolution_level,
        E2.evolution_stone as second_evolution_stone,
        E1.evolution_type as first_evolution_type,
        E2.evolution_type as second_evolution_type,
        COALESCE(E2.route_order, E1.route_order) as final_route_order,
        COALESCE(E2.earliest_game_stage, E1.earliest_game_stage) as final_game_stage
    FROM all_evolutions E1
    INNER JOIN all_evolutions E2 ON E1.evolution_name = E2.pokemon
),

-- Complete evolution chains including 3-stage lines
complete_evolution_chains AS (
    
    -- First stage evolutions
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['pokemon','evolution_name']) }} as chain_id,
        E.pokemon,
        E.evolution_name,
        E.pokemon || ' → ' || E.evolution_name as display_name,
        1 as evolution_stage,
        E.evolution_level,
        E.evolution_stone,
        E.evolution_type,
        E.earliest_route,
        E.route_order,
        E.earliest_game_stage
    FROM all_evolutions E
    
    UNION ALL
    
    -- Second stage evolutions (3-stage lines)
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['pokemon','second_evolution_name']) }} as chain_id,
        SSE.pokemon,
        SSE.second_evolution_name as evolution_name,
        SSE.pokemon || ' → ' || SSE.first_evolution_name || ' → ' || SSE.second_evolution_name as display_name,
        2 as evolution_stage,
        SSE.second_evolution_level as evolution_level,
        SSE.second_evolution_stone as evolution_stone,
        SSE.second_evolution_type as evolution_type,
        R.map as earliest_route,
        SSE.final_route_order as route_order,
        SSE.final_game_stage as earliest_game_stage
    FROM second_stage_evolutions SSE
    LEFT JOIN {{ ref('stg_game_route_order') }} R ON R.game_order = SSE.final_route_order

)

SELECT
    chain_id as evolution_id,
    PS.pokedex,
    E.pokemon,
    evolution_name,
    display_name,
    evolution_stage,
    evolution_type,
    evolution_level,
    evolution_stone,
    earliest_route,
    route_order
FROM complete_evolution_chains as E
INNER JOIN {{ ref('pkmn_stats') }} as PS on E.pokemon = PS.pokemon