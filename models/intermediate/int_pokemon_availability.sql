WITH area_order AS (
    SELECT 
        EAO.encounter_area,
        R.map,
        R."order"
    FROM {{ ref('stg_pkmn_encounter_area_order') }} as EAO 
    INNER JOIN {{ ref('stg_game_route_order') }} as R on R.map = EAO.map
),

-- Base catchable pokemon from encounter areas
base_catchable_pokemon AS (
    SELECT 
        EA.pokemon,
        EA.level,
        L.level_cap,
        EA.map,
        EA.area,
        R."order",
        R.next_gym,
        EA.pokemon as initial_pokemon,
        'Wild Encounter' as availability_source,
        CASE 
            WHEN R."order" >= EAO."order" THEN R."order" 
            ELSE EAO."order" 
        END as earliest_route
    FROM {{ ref('stg_pkmn_encounter_areas') }} as EA
    INNER JOIN {{ ref('stg_game_route_order') }} as R on R.map = EA.map
    INNER JOIN area_order as EAO on EA.area = EAO.encounter_area
    INNER JOIN {{ ref('int_game_progression') }} as L on R.next_gym = L.game_stage
),

-- Level-up evolutions from catchable pokemon
level_up_evolutions AS (
    {{ get_evolution_pokemon('base_catchable_pokemon', 'evolution_level') }}
),

-- Stone evolutions available at different locations
stone_evolutions_route7 AS (
    {{ get_stone_evolution_pokemon('base_catchable_pokemon', ['Fire', 'Water', 'Thunder', 'Leaf'], 'Route7') }}
),

stone_evolutions_mt_moon AS (
    {{ get_stone_evolution_pokemon('base_catchable_pokemon', ['Moon Stone'], 'MtMoon1F') }}
),

-- All catchable pokemon sources combined
all_catchable_sources AS (
    -- Base wild encounters
    SELECT
        pokemon,
        level,
        level_cap,
        map,
        area,
        earliest_route,
        next_gym,
        initial_pokemon,
        availability_source
    FROM base_catchable_pokemon
    
    UNION ALL
    
    -- Level-up evolutions
    SELECT
        pokemon,
        NULL as level, -- Evolutions don't have encounter levels
        level_cap,
        map,
        'Evolution' as area,
        "order" as earliest_route,
        next_gym,
        initial_pokemon,
        'Level Evolution' as availability_source
    FROM level_up_evolutions
    
    UNION ALL
    
    -- Stone evolutions (Route 7 - Celadon City)
    SELECT
        pokemon,
        NULL as level,
        level_cap,
        map,
        'Stone Evolution' as area,
        "order" as earliest_route,
        next_gym,
        initial_pokemon,
        'Stone Evolution (Route 7)' as availability_source
    FROM stone_evolutions_route7
    
    UNION ALL
    
    -- Stone evolutions (Mt. Moon)
    SELECT
        pokemon,
        NULL as level,
        level_cap,
        map,
        'Stone Evolution' as area,
        "order" as earliest_route,
        next_gym,
        initial_pokemon,
        'Stone Evolution (Mt. Moon)' as availability_source
    FROM stone_evolutions_mt_moon
),

-- Find first catch opportunity for each pokemon
first_catch_opportunity AS (
    SELECT 
        pokemon,
        MIN(earliest_route) as earliest_route
    FROM all_catchable_sources as P
    INNER JOIN {{ ref('stg_game_route_order') }} as R ON P.earliest_route <= R."order"
    GROUP BY pokemon
),

-- Team options: Pokemon available at each game stage
team_availability AS (
    SELECT 
        R.map,
        R."order",
        R.next_gym,
        F.pokemon as initial_pokemon,
        L.level_cap,
        F.pokemon,
        'Base Pokemon' as team_source
    FROM {{ ref('stg_game_route_order') }} as R
    INNER JOIN first_catch_opportunity as F ON F.earliest_route <= R."order"
    INNER JOIN {{ ref('int_game_progression') }} as L ON L.game_stage = R.next_gym
),

-- Add evolutions available for team building
team_level_evolutions AS (
    {{ get_evolution_pokemon('team_availability', 'evolution_level') }}
),

team_stone_evolutions_route7 AS (
    {{ get_stone_evolution_pokemon('team_availability', ['"Water Stone"', '"Fire Stone"', '"Leaf Stone"', '"Thunder Stone"'], 'Route7') }}
),

team_stone_evolutions_mt_moon AS (
    {{ get_stone_evolution_pokemon('team_availability', ['"Moon Stone"'], 'MtMoon1F') }}
),

-- All team building options
all_team_options AS (
    SELECT * FROM team_availability
    
    UNION ALL 
    
    SELECT 
        map, "order", next_gym, initial_pokemon, level_cap, pokemon,
        'Level Evolution' as team_source
    FROM team_level_evolutions
    
    UNION ALL
    
    SELECT 
        map, "order", next_gym, initial_pokemon, level_cap, pokemon,
        'Stone Evolution (Route 7)' as team_source
    FROM team_stone_evolutions_route7

    UNION ALL

    SELECT 
        map, "order", next_gym, initial_pokemon, level_cap, pokemon,
        'Stone Evolution (Mt. Moon)' as team_source
    FROM team_stone_evolutions_mt_moon
),

-- Final comprehensive pokemon availability
pokemon_availability AS (
    -- Catchable pokemon with encounter details
    SELECT
        {{ dbt_utils.generate_surrogate_key(['pokemon','COALESCE(level, 0)','map','area','earliest_route']) }} as id,
        'Catchable' as availability_type,
        pokemon,
        initial_pokemon,
        level as encounter_level,
        level_cap,
        map,
        area,
        earliest_route,
        next_gym as game_stage,
        availability_source,
        NULL as team_source
    FROM all_catchable_sources
    
    UNION
    
    -- Team building options
    SELECT
        {{ dbt_utils.generate_surrogate_key(['pokemon','map','"order"','initial_pokemon']) }} as id,
        'Team Option' as availability_type,
        pokemon,
        initial_pokemon,
        NULL as encounter_level,
        level_cap,
        map,
        NULL as area,
        "order" as earliest_route,
        next_gym as game_stage,
        NULL as availability_source,
        team_source
    FROM all_team_options
)

SELECT 
    id,
    availability_type,
    pokemon,
    initial_pokemon,
    encounter_level,
    level_cap,
    map,
    area,
    earliest_route,
    game_stage,
    COALESCE(availability_source, team_source) as source,
    -- Add helpful derived fields
    CASE 
        WHEN availability_type = 'Catchable' AND area = 'Evolution' THEN 'Evolved Form'
        WHEN availability_type = 'Catchable' AND area = 'Stone Evolution' THEN 'Stone Evolved Form'
        WHEN availability_type = 'Team Option' AND team_source LIKE '%Evolution%' THEN 'Team Evolution Option'
        WHEN availability_type = 'Catchable' THEN 'Wild Pokemon'
        ELSE 'Team Building Option'
    END as pokemon_category,
    CASE 
        WHEN pokemon = initial_pokemon THEN 0
        WHEN source LIKE '%Level Evolution%' THEN 1
        WHEN source LIKE '%Stone Evolution%' THEN 2
        ELSE 0
    END as evolution_stage
FROM pokemon_availability