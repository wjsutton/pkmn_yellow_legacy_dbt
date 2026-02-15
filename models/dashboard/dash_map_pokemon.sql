-- dash_map_pokemon: Map locations with catchable pokemon and key catch flags.
-- Grain: one row per (display_location, game_stage, pokemon, area)

WITH location_coords AS (
    -- Join game routes -> map location groups -> map locations to get coordinates.
    -- Collapse multi-floor dungeons (e.g. MtMoon1F/B1F/B2F -> MtMoon).
    SELECT
        gro.map AS game_route_map,
        gro.next_gym AS game_stage,
        mlg.map_location,
        ml.display_name,
        ml.x_coordinate,
        ml.y_coordinate,
        ml.location_type
    FROM {{ ref('stg_game_route_order') }} gro
    INNER JOIN {{ ref('stg_map_location_groups') }} mlg
        ON mlg.game_route_map = gro.map
    INNER JOIN {{ ref('stg_map_locations') }} ml
        ON ml.map = mlg.map_location
    WHERE gro.next_gym NOT IN ('Rematches', 'PostGame')
),

catchable_pokemon AS (
    -- Filter availability to only catchable pokemon (wild, evolution, stone evo)
    SELECT
        pa.pokemon,
        pa.initial_pokemon,
        pa.encounter_level,
        pa.map,
        pa.area,
        pa.game_stage,
        pa.source,
        pa.pokemon_category
    FROM {{ ref('int_pokemon_availability') }} pa
    WHERE pa.availability_type = 'Catchable'
),

-- Key catches: pokemon that appear on any recommended or min-exp team
-- across all variants for the current or future stages.
recommended_pokemon AS (
    SELECT DISTINCT player_pokemon AS pokemon
    FROM {{ ref('opt_recommended_teams') }}
),

min_exp_pokemon AS (
    SELECT DISTINCT pokemon
    FROM {{ ref('opt_min_exp_squads') }}
),

key_catches AS (
    SELECT DISTINCT pokemon
    FROM (
        SELECT pokemon FROM recommended_pokemon
        UNION
        SELECT pokemon FROM min_exp_pokemon
    )
),

-- Join catchable pokemon to location coords, then flag key catches
joined AS (
    SELECT
        lc.display_name AS display_location,
        lc.display_name,
        lc.x_coordinate,
        lc.y_coordinate,
        lc.location_type,
        ca.game_stage,
        ca.pokemon,
        ca.area,
        MIN(ca.source) AS source,
        MIN(ca.pokemon_category) AS pokemon_category,
        MIN(ca.initial_pokemon) AS initial_pokemon,
        MIN(ca.encounter_level) AS min_encounter_level,
        MAX(ca.encounter_level) AS max_encounter_level,
        CASE WHEN kc.pokemon IS NOT NULL THEN 1 ELSE 0 END AS is_key_catch
    FROM catchable_pokemon ca
    INNER JOIN location_coords lc
        ON lc.game_route_map = ca.map
        AND lc.game_stage = ca.game_stage
    LEFT JOIN key_catches kc
        ON kc.pokemon = ca.pokemon
    GROUP BY
        lc.display_name,
        lc.x_coordinate,
        lc.y_coordinate,
        lc.location_type,
        ca.game_stage,
        ca.pokemon,
        ca.area,
        CASE WHEN kc.pokemon IS NOT NULL THEN 1 ELSE 0 END
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['display_location', 'game_stage', 'pokemon', 'area']) }} AS surrogate_key,
    display_location,
    display_name,
    x_coordinate,
    y_coordinate,
    location_type,
    game_stage,
    pokemon,
    initial_pokemon,
    area,
    min_encounter_level,
    max_encounter_level,
    source,
    pokemon_category,
    is_key_catch
FROM joined
