WITH base_evolutions AS (
    SELECT 
        E.pokedex,
        E.pokemon as base_pokemon,
        E.evolution_level,
        E.evolution_stone,
        E.evolution_name as evolved_pokemon,
        PS1.type1 as base_type1,
        PS1.type2 as base_type2,
        PS2.type1 as evolved_type1,
        PS2.type2 as evolved_type2
    FROM {{ ref('stg_pkmn_evolutions') }} E
    INNER JOIN {{ ref('stg_pkmn_stats') }} PS1 ON E.pokemon = PS1.pokemon
    INNER JOIN {{ ref('stg_pkmn_stats') }} PS2 ON E.evolution_name = PS2.pokemon
),

-- Stone evolution locations and route availability
stone_evolution_routes AS (
    SELECT 
        'Fire' as stone_name,
        'Route7' as earliest_route,
        7 as route_order
    UNION ALL
    SELECT 'Water', 'Route7', 7
    UNION ALL
    SELECT 'Thunder', 'Route7', 7
    UNION ALL
    SELECT 'Leaf', 'Route7', 7
    UNION ALL
    SELECT 'Moon', 'MtMoon1F', 3
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
        {{ dbt_utils.generate_surrogate_key(['base_pokemon','evolved_pokemon']) }} as id,
        base_pokemon,
        evolved_pokemon,
        evolution_level,
        evolution_stone,
        base_type1,
        base_type2,
        evolved_type1,
        evolved_type2,
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
        {{ dbt_utils.generate_surrogate_key(['base_pokemon','evolved_pokemon']) }} as id,
        base_pokemon,
        evolved_pokemon,
        evolution_level,
        evolution_stone,
        base_type1,
        base_type2,
        evolved_type1,
        evolved_type2,
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
        E1.base_pokemon as original_base,
        E1.evolved_pokemon as intermediate_form,
        E2.evolved_pokemon as final_form,
        E1.evolution_level as first_evolution_level,
        E1.evolution_stone as first_evolution_stone,
        E2.evolution_level as second_evolution_level,
        E2.evolution_stone as second_evolution_stone,
        E1.evolution_type as first_evolution_type,
        E2.evolution_type as second_evolution_type,
        -- Use the later route/stage for availability
        COALESCE(E2.route_order, E1.route_order) as final_route_order,
        COALESCE(E2.earliest_game_stage, E1.earliest_game_stage) as final_game_stage
    FROM all_evolutions E1
    INNER JOIN all_evolutions E2 ON E1.evolved_pokemon = E2.base_pokemon
),

-- Complete evolution chains including 3-stage lines
complete_evolution_chains AS (
    -- Base pokemon (stage 0)
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['pokemon','pokemon']) }} as chain_id,
        PS.pokemon as base_pokemon,
        PS.pokemon as current_form,
        PS.pokemon as display_name,
        0 as evolution_stage,
        NULL as evolution_level_required,
        NULL as evolution_stone_required,
        NULL as evolution_type,
        NULL as earliest_route,
        NULL as route_order,
        NULL as earliest_game_stage,
        PS.type1,
        PS.type2
    FROM {{ ref('stg_pkmn_stats') }} PS
    
    UNION ALL
    
    -- First stage evolutions
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['base_pokemon','evolved_pokemon']) }} as chain_id,
        E.base_pokemon,
        E.evolved_pokemon as current_form,
        E.base_pokemon || ' → ' || E.evolved_pokemon as display_name,
        1 as evolution_stage,
        E.evolution_level as evolution_level_required,
        E.evolution_stone as evolution_stone_required,
        E.evolution_type,
        E.earliest_route,
        E.route_order,
        E.earliest_game_stage,
        E.evolved_type1 as type1,
        E.evolved_type2 as type2
    FROM all_evolutions E
    
    UNION ALL
    
    -- Second stage evolutions (3-stage lines)
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['original_base','final_form']) }} as chain_id,
        SSE.original_base as base_pokemon,
        SSE.final_form as current_form,
        SSE.original_base || ' → ' || SSE.intermediate_form || ' → ' || SSE.final_form as display_name,
        2 as evolution_stage,
        SSE.second_evolution_level as evolution_level_required,
        SSE.second_evolution_stone as evolution_stone_required,
        SSE.second_evolution_type as evolution_type,
        R.map as earliest_route,
        SSE.final_route_order as route_order,
        SSE.final_game_stage as earliest_game_stage,
        PS.type1,
        PS.type2
    FROM second_stage_evolutions SSE
    INNER JOIN {{ ref('stg_pkmn_stats') }} PS ON SSE.final_form = PS.pokemon
    LEFT JOIN {{ ref('stg_game_route_order') }} R ON R.order = SSE.final_route_order
)

SELECT 
    chain_id,
    base_pokemon,
    current_form,
    display_name,
    evolution_stage,
    evolution_level_required,
    evolution_stone_required,
    evolution_type,
    earliest_route,
    route_order,
    earliest_game_stage,
    type1,
    type2,
    -- Add helpful classification flags
    CASE WHEN evolution_stage = 0 THEN 1 ELSE 0 END as is_base_form,
    CASE WHEN evolution_stage > 0 THEN 1 ELSE 0 END as is_evolved_form,
    CASE WHEN evolution_type = 'Stone' THEN 1 ELSE 0 END as requires_stone,
    CASE WHEN evolution_type = 'Level' THEN 1 ELSE 0 END as requires_level,
    -- Add evolution viability at different game stages
    CASE 
        WHEN evolution_stage = 0 THEN 'Always Available'
        WHEN evolution_type = 'Level' THEN 'Available when level reached'
        WHEN evolution_type = 'Stone' AND route_order <= 3 THEN 'Available from Mt. Moon'
        WHEN evolution_type = 'Stone' AND route_order <= 7 THEN 'Available from Celadon City'
        ELSE 'Availability depends on route progression'
    END as availability_description
FROM complete_evolution_chains
ORDER BY base_pokemon, evolution_stage