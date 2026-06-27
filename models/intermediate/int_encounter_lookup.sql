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

catch_rates AS (
    SELECT pokemon AS cr_pokemon, catch_rate
    FROM {{ ref('stg_pkmn_catch_rates') }}
),

encounter_rates AS (
    -- Per-map encounter rate byte (rate/256 = P(encounter per eligible step)).
    SELECT map AS er_map, grass_rate, water_rate
    FROM {{ ref('stg_pkmn_encounter_rates') }}
),

area_wild_exp AS (
    -- Expected wild EXP of a random battle in each (map, area): the EXP a team
    -- member would gain per battle fought while hunting here. Probability-weighted
    -- across the area's encounter slots (floor(base_exp * level / 7), Gen-1 wild formula).
    SELECT
        ea.map AS awe_map,
        ea.area AS awe_area,
        SUM(ea.encounter_probability * {{ calculate_wild_exp('be.base_exp', 'ea.level') }})
            / NULLIF(SUM(ea.encounter_probability), 0) AS avg_wild_exp
    FROM {{ ref('stg_pkmn_encounter_areas') }} ea
    INNER JOIN {{ ref('stg_pkmn_base_exp') }} be ON ea.pokemon = be.pokemon
    GROUP BY ea.map, ea.area
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
        ml.nav_map_name,
        er.grass_rate,
        er.water_rate,
        awe.avg_wild_exp
    FROM encounters e
    LEFT JOIN area_metadata am ON e.area = am.area
    LEFT JOIN route_order ro ON e.map = ro.map
    LEFT JOIN map_name_lookup ml ON e.map = ml.encounter_map
    LEFT JOIN encounter_rates er ON e.map = er.er_map
    LEFT JOIN area_wild_exp awe ON e.map = awe.awe_map AND e.area = awe.awe_area
    GROUP BY
        e.pokemon, e.map, e.area,
        am.encounter_method, am.required_badge_count, am.required_item,
        am.tile_type, am.area_order,
        ro.next_gym, ro.game_order,
        ml.nav_map_name,
        er.grass_rate, er.water_rate, awe.avg_wild_exp
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
    nav_map_name,
    -- Per-map encounter rate byte (data/wild/maps/*.asm). The effective rate for
    -- THIS area is the grass byte on grass tiles, the water byte on water tiles.
    grass_rate,
    water_rate,
    CASE
        WHEN tile_type = 'water' THEN water_rate
        WHEN tile_type = 'grass' THEN grass_rate
        ELSE NULL
    END AS encounter_rate,
    -- P(encounter on a given eligible step) = rate / 256.
    ROUND(
        CASE
            WHEN tile_type = 'water' THEN water_rate
            WHEN tile_type = 'grass' THEN grass_rate
            ELSE NULL
        END / 256.0, 4
    ) AS pct_per_step,
    -- Expected eligible steps to MEET this species:
    --   1 / [ (rate/256) * P(species | encounter) ].
    ROUND(
        1.0 / NULLIF(
            (CASE
                WHEN tile_type = 'water' THEN water_rate
                WHEN tile_type = 'grass' THEN grass_rate
                ELSE NULL
            END / 256.0) * total_probability, 0
        ), 1
    ) AS expected_steps_to_meet,
    -- Expected wild EXP of a random battle in this area (opportunity cost per battle).
    ROUND(avg_wild_exp, 1) AS avg_wild_exp,
    -- Capture difficulty (independent of encounter rarity above).
    -- catch_rate is the Gen-1 0-255 byte; higher = easier to catch.
    cr.catch_rate,
    CASE
        WHEN cr.catch_rate IS NULL THEN NULL
        WHEN cr.catch_rate >= 200 THEN 'Very Easy'
        WHEN cr.catch_rate >= 120 THEN 'Easy'
        WHEN cr.catch_rate >= 75  THEN 'Moderate'
        WHEN cr.catch_rate >= 45  THEN 'Hard'
        ELSE 'Very Hard'
    END AS catch_difficulty
FROM aggregated a
LEFT JOIN catch_rates cr ON a.pokemon = cr.cr_pokemon
