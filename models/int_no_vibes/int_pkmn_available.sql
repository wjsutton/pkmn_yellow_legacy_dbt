WITH area_order AS (
    SELECT
        eao.encounter_area,
        r.map,
        r.game_order
    FROM {{ ref('stg_pkmn_encounter_area_order') }} AS eao
    INNER JOIN {{ ref('stg_game_route_order') }} AS r ON eao.map = r.map
),

-- Base catchable pokemon from encounter areas
base_catchable_pokemon AS (
    SELECT
        ea.pokemon,
        CASE
            WHEN r.game_order >= eao.game_order THEN r.game_order
            ELSE eao.game_order
        END AS game_order
    FROM {{ ref('stg_pkmn_encounter_areas') }} AS ea
    INNER JOIN {{ ref('stg_game_route_order') }} AS r ON ea.map = r.map
    INNER JOIN area_order AS eao ON ea.area = eao.encounter_area
),

available_from AS (
    SELECT
        pokemon,
        MIN(game_order) AS earliest_game_stage
    FROM base_catchable_pokemon
    GROUP BY pokemon
),

base_catchable_pokemon_by_future_routes AS (
    SELECT
        a.pokemon,
        l.level_cap,
        r.game_order
    FROM available_from AS a
    INNER JOIN
        {{ ref('stg_game_route_order') }} AS r
        ON a.earliest_game_stage <= r.game_order
    INNER JOIN
        {{ ref('int_game_progression') }} AS l
        ON r.next_gym = l.game_stage
),


-- Evolved forms available from catchable pokemon using new expanded evolutions table
catchable_evolutions AS (
    SELECT
        ee.evolution_name AS pokemon,
        bcp.level_cap,
        CASE
            WHEN ee.evolution_type = 'Stone' AND ee.route_order IS NOT null
                THEN GREATEST(bcp.game_order, ee.route_order)
            ELSE bcp.game_order
        END AS game_order
    FROM base_catchable_pokemon_by_future_routes AS bcp
    INNER JOIN {{ ref('int_pkmn_evolutions_all') }} AS ee
        ON bcp.pokemon = ee.pokemon
    WHERE
        ee.evolution_stage > 0
        AND (
            -- Level evolutions available when pokemon can reach required level
            (
                ee.evolution_type = 'Level'
                AND ee.evolution_level <= bcp.level_cap
            )
            OR
            -- Stone evolutions available when stone route is accessible
            (ee.evolution_type = 'Stone' AND ee.route_order <= bcp.game_order)
        )
),

all_catchable_sources AS (

    SELECT
        pokemon,
        level_cap,
        game_order
    FROM base_catchable_pokemon_by_future_routes

    UNION ALL

    SELECT
        pokemon,
        level_cap,
        game_order
    FROM catchable_evolutions
)

SELECT
    game_order,
    pokemon,
    level_cap
FROM all_catchable_sources
