-- int_encounter_lookup: Where can I catch any Pokemon?
-- Pre-joined encounter data for agent queries.
-- Grain: one row per (pokemon, map, area)

WITH encounters AS (
    SELECT
        ea.pokemon,
        ea.map,
        ea.area,
        ea.level,
        ea.encounter_probability
    FROM {{ ref('stg_pkmn_encounter_areas') }} ea
),

area_metadata AS (
    SELECT
        eao.area,
        eao.encounter_method,
        eao.tile_type,
        eao.required_badge_count,
        eao.required_item,
        eao.area_order
    FROM {{ ref('stg_pkmn_encounter_area_order') }} eao
),

route_order AS (
    SELECT
        gro.map,
        gro.game_order,
        gro.next_gym
    FROM {{ ref('stg_game_route_order') }} gro
),

nav_map_names AS (
    SELECT DISTINCT map_name
    FROM {{ ref('stg_nav_map_tiles') }}
),

map_name_lookup AS (
    SELECT
        r.map AS encounter_map,
        n.map_name AS nav_map_name
    FROM (SELECT DISTINCT map FROM encounters) r
    CROSS JOIN nav_map_names n
    WHERE UPPER(REPLACE(r.map, ' ', '')) = REPLACE(n.map_name, '_', '')
),

aggregated AS (
    SELECT
        e.pokemon,
        e.map AS map_name,
        e.area,
        MIN(e.level) AS min_level,
        MAX(e.level) AS max_level,
        SUM(e.encounter_probability) AS total_probability,
        am.encounter_method,
        am.required_badge_count,
        am.required_item,
        am.tile_type,
        am.area_order,
        ro.next_gym AS game_stage_available,
        ro.game_order AS route_distance,
        ml.nav_map_name
    FROM encounters e
    LEFT JOIN area_metadata am ON e.area = am.area
    LEFT JOIN route_order ro ON e.map = ro.map
    LEFT JOIN map_name_lookup ml ON e.map = ml.encounter_map
    GROUP BY
        e.pokemon, e.map, e.area,
        am.encounter_method, am.required_badge_count, am.required_item,
        am.tile_type, am.area_order,
        ro.next_gym, ro.game_order,
        ml.nav_map_name
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['pokemon', 'map_name', 'area']) }} AS id,
    pokemon,
    map_name,
    area,
    min_level,
    max_level,
    total_probability,
    encounter_method,
    required_badge_count,
    required_item,
    tile_type,
    game_stage_available,
    -- Minimum badges to REACH this location (Badge_1 routes need 0, Badge_2 need 1, etc.)
    CASE
        WHEN game_stage_available LIKE 'Badge_%'
            THEN CAST(REPLACE(game_stage_available, 'Badge_', '') AS INT) - 1
        WHEN game_stage_available = 'Elite 4' THEN 8
        WHEN game_stage_available = 'Rematches' THEN 8
        ELSE 0
    END AS badges_to_reach,
    route_distance,
    nav_map_name
FROM aggregated
