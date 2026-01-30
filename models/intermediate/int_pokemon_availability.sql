-- int_pokemon_availability: What pokemon are available at each game stage?
-- Absorbs int_game_progression and int_pokemon_evolutions_expanded as CTEs

-- === Game Progression (formerly int_game_progression) ===
WITH trainer_max_levels AS (
    -- Gym Leaders
    SELECT
        G.trainer,
        G.game_stage,
        MAX(R.game_order) AS game_order,
        MAX(G.pkmn_level) AS max_level,
        'Gym Leader' as trainer_type
    FROM {{ ref('stg_trainers_gym_leaders') }} AS G
    INNER JOIN {{ ref('stg_game_route_order') }} AS R
        ON G.nearest_route = R.map
    GROUP BY G.trainer, G.game_stage

    UNION ALL

    -- Legendary trainers (Smith)
    SELECT
        G.trainer,
        G.game_stage,
        MAX(R.game_order) AS game_order,
        MAX(G.pkmn_level) AS max_level,
        'Legendary' as trainer_type
    FROM {{ ref('stg_trainers_legendary') }} AS G
    INNER JOIN {{ ref('stg_game_route_order') }} AS R
        ON G.nearest_route = R.map
    WHERE G.trainer = 'Smith'
    GROUP BY G.trainer, G.game_stage
),

level_caps AS (
    SELECT DISTINCT
        G.game_stage,
        MAX(CASE
            WHEN G.game_stage = 'Badge_3' THEN 24
            ELSE G.max_level
        END) AS level_cap
    FROM trainer_max_levels AS G
    INNER JOIN {{ ref('stg_game_route_order') }} AS R
        ON R.game_order <= G.game_order
    GROUP BY G.game_stage
),

route_mapping AS (
    SELECT
        next_gym,
        MAX(game_order) AS last_order
    FROM {{ ref('stg_game_route_order') }}
    GROUP BY next_gym
),

final_caps AS (
    SELECT
        lc.game_stage,
        lc.level_cap,
        rm.last_order
    FROM level_caps lc
    LEFT JOIN route_mapping rm
        ON rm.next_gym = LEFT(lc.game_stage, 7)
),

game_progression AS (
    SELECT
        game_stage,
        level_cap,
        COALESCE(
            last_order,
            MAX(last_order) OVER (
                ORDER BY level_cap
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            )
        ) AS stage_order
    FROM final_caps
),

-- === Pokemon Evolutions Expanded (formerly int_pokemon_evolutions_expanded) ===
base_evolutions AS (
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

stone_evolution_routes AS (
    SELECT
        stone_name,
        earliest_route,
        R.game_order as route_order
    FROM (
        SELECT 'Fire' as stone_name, 'Route7' as earliest_route
        UNION ALL
        SELECT 'Water', 'Route7'
        UNION ALL
        SELECT 'Thunder', 'Route7'
        UNION ALL
        SELECT 'Leaf', 'Route7'
        UNION ALL
        SELECT 'Moon', 'MtMoon1F'
    ) stone_locations
    INNER JOIN {{ ref('stg_game_route_order') }} R ON R.map = stone_locations.earliest_route
),

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

level_evolutions AS (
    SELECT
        E.*,
        NULL as earliest_route,
        NULL as route_order,
        NULL as earliest_game_stage
    FROM base_evolutions E
    WHERE E.evolution_level IS NOT NULL
),

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
        COALESCE(E2.route_order, E1.route_order) as final_route_order,
        COALESCE(E2.earliest_game_stage, E1.earliest_game_stage) as final_game_stage
    FROM all_evolutions E1
    INNER JOIN all_evolutions E2 ON E1.evolved_pokemon = E2.base_pokemon
),

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
        NULL as evo_earliest_route,
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
        E.base_pokemon || ' -> ' || E.evolved_pokemon as display_name,
        1 as evolution_stage,
        E.evolution_level as evolution_level_required,
        E.evolution_stone as evolution_stone_required,
        E.evolution_type,
        E.earliest_route as evo_earliest_route,
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
        SSE.original_base || ' -> ' || SSE.intermediate_form || ' -> ' || SSE.final_form as display_name,
        2 as evolution_stage,
        SSE.second_evolution_level as evolution_level_required,
        SSE.second_evolution_stone as evolution_stone_required,
        SSE.second_evolution_type as evolution_type,
        R.map as evo_earliest_route,
        SSE.final_route_order as route_order,
        SSE.final_game_stage as earliest_game_stage,
        PS.type1,
        PS.type2
    FROM second_stage_evolutions SSE
    INNER JOIN {{ ref('stg_pkmn_stats') }} PS ON SSE.final_form = PS.pokemon
    LEFT JOIN {{ ref('stg_game_route_order') }} R ON R.game_order = SSE.final_route_order
),

pokemon_evolutions_expanded AS (
    SELECT
        chain_id,
        base_pokemon,
        current_form,
        display_name,
        evolution_stage,
        evolution_level_required,
        evolution_stone_required,
        evolution_type,
        evo_earliest_route,
        route_order,
        earliest_game_stage,
        type1,
        type2,
        CASE WHEN evolution_stage = 0 THEN 1 ELSE 0 END as is_base_form,
        CASE WHEN evolution_stage > 0 THEN 1 ELSE 0 END as is_evolved_form,
        CASE WHEN evolution_type = 'Stone' THEN 1 ELSE 0 END as requires_stone,
        CASE WHEN evolution_type = 'Level' THEN 1 ELSE 0 END as requires_level,
        CASE
            WHEN evolution_stage = 0 THEN 'Always Available'
            WHEN evolution_type = 'Level' THEN 'Available when level reached'
            WHEN evolution_type = 'Stone' AND route_order <= 3 THEN 'Available from Mt. Moon'
            WHEN evolution_type = 'Stone' AND route_order <= 7 THEN 'Available from Celadon City'
            ELSE 'Availability depends on route progression'
        END as availability_description
    FROM complete_evolution_chains
),

-- === Pokemon Availability (original logic, now using CTEs above) ===
area_order AS (
    SELECT
        EAO.encounter_area,
        R.map,
        R.game_order
    FROM {{ ref('stg_pkmn_encounter_area_order') }} as EAO
    INNER JOIN {{ ref('stg_game_route_order') }} as R on R.map = EAO.map
),

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
    INNER JOIN game_progression as L on R.next_gym = L.game_stage
),

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
        CASE
            WHEN EE.evolution_type = 'Stone' AND EE.route_order IS NOT NULL
                THEN GREATEST(BCP.earliest_route, EE.route_order)
            ELSE BCP.earliest_route
        END as earliest_route
    FROM base_catchable_pokemon BCP
    INNER JOIN pokemon_evolutions_expanded EE
        ON BCP.pokemon = EE.base_pokemon
    WHERE EE.evolution_stage > 0
        AND (
            (EE.evolution_type = 'Level' AND EE.evolution_level_required <= BCP.level_cap)
            OR
            (EE.evolution_type = 'Stone' AND EE.route_order <= BCP.game_order)
        )
),

all_catchable_sources AS (
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

    SELECT
        pokemon,
        NULL as pkmn_level,
        level_cap,
        map,
        area,
        earliest_route,
        next_gym,
        initial_pokemon,
        availability_source
    FROM catchable_evolutions
),

first_catch_opportunity AS (
    SELECT
        pokemon,
        MIN(earliest_route) as earliest_route
    FROM all_catchable_sources
    GROUP BY pokemon
),

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
    INNER JOIN game_progression as L ON L.game_stage = R.next_gym
),

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
    INNER JOIN pokemon_evolutions_expanded EE
        ON TA.pokemon = EE.base_pokemon
    WHERE EE.evolution_stage > 0
        AND (
            (EE.evolution_type = 'Level' AND EE.evolution_level_required <= TA.level_cap)
            OR
            (EE.evolution_type = 'Stone' AND EE.route_order <= TA.game_order)
        )
),

all_team_options AS (
    SELECT * FROM team_availability
    UNION ALL
    SELECT * FROM team_evolutions
),

pokemon_availability AS (
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
