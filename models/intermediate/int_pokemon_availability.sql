WITH area_order AS (
    SELECT 
        EAO.encounter_area,
        R.map,
        R.game_order
    FROM {{ ref('stg_pkmn_encounter_area_order') }} as EAO 
    INNER JOIN {{ ref('stg_game_route_order') }} as R on R.map = EAO.map
),

-- Base catchable pokemon from encounter areas
base_catchable_pokemon AS (
    SELECT 
        EA.pokemon,
        EA.pkmn_level,
        L.level_cap,
        EA.map,
        EA.area,
        R.game_order,
        R.next_gym,
        EA.pokemon as initial_pokemon,
        'Wild Encounter' as availability_source,
        CASE 
            WHEN R.game_order >= EAO.game_order THEN R.game_order 
            ELSE EAO.game_order
        END as earliest_route
    FROM {{ ref('stg_pkmn_encounter_areas') }} as EA
    INNER JOIN {{ ref('stg_game_route_order') }} as R on R.map = EA.map
    INNER JOIN area_order as EAO on EA.area = EAO.encounter_area
    INNER JOIN {{ ref('int_game_progression') }} as L on R.next_gym = L.game_stage
),

-- Evolved forms available from catchable pokemon using new expanded evolutions table
catchable_evolutions AS (
    SELECT 
        BCP.initial_pokemon,
        EE.current_form as pokemon,
        BCP.pkmn_level,
        BCP.level_cap,
        BCP.map,
        CASE 
            WHEN EE.evolution_type = 'Stone' THEN 'Stone Evolution'
            WHEN EE.evolution_type = 'Level' THEN 'Evolution'
            ELSE 'Evolution'
        END as area,
        BCP.game_order,
        BCP.next_gym,
        CASE 
            WHEN EE.evolution_type = 'Stone' THEN EE.availability_description
            WHEN EE.evolution_type = 'Level' THEN 'Level Evolution'
            ELSE 'Evolution Available'
        END as availability_source,
        -- For stone evolutions, use the stone availability route
        -- For level evolutions, use the base pokemon's earliest route
        CASE 
            WHEN EE.evolution_type = 'Stone' AND EE.route_order IS NOT NULL 
                THEN GREATEST(BCP.earliest_route, EE.route_order)
            ELSE BCP.earliest_route
        END as earliest_route
    FROM base_catchable_pokemon BCP
    INNER JOIN {{ ref('int_pokemon_evolutions_expanded') }} EE 
        ON BCP.pokemon = EE.base_pokemon
    WHERE EE.evolution_stage > 0  -- Only evolved forms
        AND (
            -- Level evolutions available when pokemon can reach required level
            (EE.evolution_type = 'Level' AND EE.evolution_level_required <= BCP.level_cap)
            OR 
            -- Stone evolutions available when stone route is accessible
            (EE.evolution_type = 'Stone' AND EE.route_order <= BCP.game_order)
        )
),

-- All catchable pokemon sources combined (simplified)
all_catchable_sources AS (
    -- Base wild encounters
    SELECT
        pokemon,
        pkmn_level,
        level_cap,
        map,
        area,
        earliest_route,
        next_gym,
        initial_pokemon,
        availability_source
    FROM base_catchable_pokemon
    
    UNION ALL
    
    -- All evolutions from catchable pokemon
    SELECT
        pokemon,
        NULL as pkmn_level, -- Evolutions don't have specific encounter levels
        level_cap,
        map,
        area,
        earliest_route,
        next_gym,
        initial_pokemon,
        availability_source
    FROM catchable_evolutions
),

-- Find first catch opportunity for each pokemon (unchanged logic)
first_catch_opportunity AS (
    SELECT 
        pokemon,
        MIN(earliest_route) as earliest_route
    FROM all_catchable_sources
    GROUP BY pokemon
),

-- Team building options: Pokemon available at each game stage (simplified)
team_availability AS (
    SELECT 
        R.map,
        R.game_order,
        R.next_gym,
        F.pokemon as initial_pokemon,
        L.level_cap,
        F.pokemon,
        'Base Pokemon' as team_source
    FROM {{ ref('stg_game_route_order') }} as R
    INNER JOIN first_catch_opportunity as F ON F.earliest_route <= R.game_order
    INNER JOIN {{ ref('int_game_progression') }} as L ON L.game_stage = R.next_gym
),

-- Team evolution options using expanded evolutions table
team_evolutions AS (
    SELECT 
        TA.map,
        TA.game_order,
        TA.next_gym,
        TA.initial_pokemon,
        TA.level_cap,
        EE.current_form as pokemon,
        CASE 
            WHEN EE.evolution_type = 'Stone' THEN EE.availability_description
            WHEN EE.evolution_type = 'Level' THEN 'Level Evolution'
            ELSE 'Evolution Available'
        END as team_source
    FROM team_availability TA
    INNER JOIN {{ ref('int_pokemon_evolutions_expanded') }} EE 
        ON TA.pokemon = EE.base_pokemon
    WHERE EE.evolution_stage > 0  -- Only evolved forms
        AND (
            -- Level evolutions available when pokemon can reach required level
            (EE.evolution_type = 'Level' AND EE.evolution_level_required <= TA.level_cap)
            OR 
            -- Stone evolutions available when stone route is accessible
            (EE.evolution_type = 'Stone' AND EE.route_order <= TA.game_order)
        )
),

-- All team building options (simplified)
all_team_options AS (
    SELECT * FROM team_availability
    UNION ALL 
    SELECT * FROM team_evolutions
),

-- Final comprehensive pokemon availability (with deduplication fix)
pokemon_availability AS (
    -- Catchable pokemon with encounter details
    SELECT DISTINCT
        {{ dbt_utils.generate_surrogate_key(['pokemon','initial_pokemon','COALESCE(pkmn_level, 0)','map','area','earliest_route','next_gym']) }} as id,
        'Catchable' as availability_type,
        pokemon,
        initial_pokemon,
        pkmn_level as encounter_level,
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
    SELECT DISTINCT
        {{ dbt_utils.generate_surrogate_key(['pokemon','map','game_order','initial_pokemon','next_gym']) }} as id,
        'Team Option' as availability_type,
        pokemon,
        initial_pokemon,
        NULL as encounter_level,
        level_cap,
        map,
        NULL as area,
        game_order as earliest_route,
        next_gym as game_stage,
        NULL as availability_source,
        team_source
    FROM all_team_options
)

-- Final output maintains same structure as original
SELECT DISTINCT
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
    -- Add helpful derived fields (same as original)
    CASE 
        WHEN availability_type = 'Catchable' AND area = 'Evolution' THEN 'Evolved Form'
        WHEN availability_type = 'Catchable' AND area = 'Stone Evolution' THEN 'Stone Evolved Form'
        WHEN availability_type = 'Team Option' AND team_source LIKE '%Evolution%' THEN 'Team Evolution Option'
        WHEN availability_type = 'Catchable' THEN 'Wild Pokemon'
        ELSE 'Team Building Option'
    END as pokemon_category,
    CASE 
        WHEN pokemon = initial_pokemon THEN 0
        WHEN COALESCE(availability_source, team_source) LIKE '%Level Evolution%' THEN 1
        WHEN COALESCE(availability_source, team_source) LIKE '%Stone Evolution%' THEN 2
        ELSE 0
    END as evolution_stage
FROM pokemon_availability