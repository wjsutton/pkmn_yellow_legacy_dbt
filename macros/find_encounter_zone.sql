{% macro find_encounter_zone(pokemon, map_name, player_x, player_y, badge_count=0, area_filter=none) %}
{#
  Find encounter zones for a specific Pokemon relative to player position.
  Supports all encounter types (Grass, Surf, Fishing, Gift, Trade, etc.)

  If the target Pokemon has no wild encounters, automatically walks back the
  evolution chain (up to 2 steps) to find catchable pre-evolutions.
  Returns evolution context so you know what to catch and how to evolve.

  Parameters:
    pokemon      - Pokemon name to search for (or its evolution)
    map_name     - Current map in UPPER_SNAKE_CASE (e.g. 'ROUTE_1')
    player_x     - Current X coordinate
    player_y     - Current Y coordinate
    badge_count  - Number of badges collected. Filters by:
                   1) Can the player REACH the location? (badges_to_reach)
                   2) Can the player USE the encounter method? (required_badge_count)
    area_filter  - Optional: limit to specific area type (e.g. 'Grass', 'Surf')

  Usage:
    {{ find_encounter_zone('Pidgey', 'ROUTE_1', 5, 10) }}
    {{ find_encounter_zone('Nidoking', 'CERULEAN_CITY', 5, 5, badge_count=2) }}
    {{ find_encounter_zone('Magikarp', 'VIRIDIAN_CITY', 5, 5, badge_count=0, area_filter='OldRod') }}
#}

WITH evolution_chain AS (
    -- Build the chain: target ← pre-evo ← pre-pre-evo
    -- Step 0: the target itself
    SELECT
        '{{ pokemon }}' AS target_pokemon,
        '{{ pokemon }}' AS catch_pokemon,
        NULL AS evolve_via,
        NULL AS evolve_detail,
        0 AS evo_steps

    UNION ALL

    -- Step 1: immediate pre-evolution (e.g. Nidorino → Nidoking)
    SELECT
        '{{ pokemon }}' AS target_pokemon,
        e1.pokemon AS catch_pokemon,
        CASE
            WHEN e1.evolution_level IS NOT NULL THEN 'Level ' || e1.evolution_level
            WHEN e1.evolution_stone IS NOT NULL THEN e1.evolution_stone || ' Stone'
            ELSE 'Special'
        END AS evolve_via,
        e1.pokemon || ' -> ' || e1.evolution_name AS evolve_detail,
        1 AS evo_steps
    FROM {{ ref('stg_pkmn_evolutions') }} e1
    WHERE LOWER(e1.evolution_name) = LOWER('{{ pokemon }}')
      AND (e1.evolution_level IS NOT NULL OR e1.evolution_stone IS NOT NULL)

    UNION ALL

    -- Step 2: two steps back (e.g. Nidoran-m → Nidorino → Nidoking)
    SELECT
        '{{ pokemon }}' AS target_pokemon,
        e2.pokemon AS catch_pokemon,
        CASE
            WHEN e2.evolution_level IS NOT NULL THEN 'Level ' || e2.evolution_level
            WHEN e2.evolution_stone IS NOT NULL THEN e2.evolution_stone || ' Stone'
            ELSE 'Special'
        END AS evolve_via,
        e2.pokemon || ' -> ' || e2.evolution_name || ' -> ' || e1.evolution_name AS evolve_detail,
        2 AS evo_steps
    FROM {{ ref('stg_pkmn_evolutions') }} e1
    INNER JOIN {{ ref('stg_pkmn_evolutions') }} e2
        ON LOWER(e2.evolution_name) = LOWER(e1.pokemon)
    WHERE LOWER(e1.evolution_name) = LOWER('{{ pokemon }}')
      AND (e2.evolution_level IS NOT NULL OR e2.evolution_stone IS NOT NULL)
),

-- Find which catch_pokemon actually exist in the encounter lookup
encounter_data AS (
    SELECT
        ec.target_pokemon,
        ec.catch_pokemon,
        ec.evolve_via,
        ec.evolve_detail,
        ec.evo_steps,
        el.pokemon,
        el.map_name AS encounter_map,
        el.area,
        el.min_level,
        el.max_level,
        el.total_probability,
        el.encounter_method,
        el.tile_type,
        el.required_badge_count,
        el.badges_to_reach,
        el.route_distance,
        el.nav_map_name
    FROM evolution_chain ec
    INNER JOIN {{ ref('int_encounter_lookup') }} el
        ON LOWER(el.pokemon) = LOWER(ec.catch_pokemon)
    WHERE el.badges_to_reach <= {{ badge_count }}
      AND el.required_badge_count <= {{ badge_count }}
      {% if area_filter is not none %}
      AND el.area = '{{ area_filter }}'
      {% endif %}
),

-- Count results per evo tier, then include the next tier if fewer than 3
tier_counts AS (
    SELECT
        evo_steps,
        COUNT(*) AS tier_count
    FROM encounter_data
    GROUP BY evo_steps
),

included_tiers AS (
    -- Always include the best (lowest) tier
    SELECT MIN(evo_steps) AS evo_steps FROM encounter_data

    UNION

    -- Include the next tier if the best tier has fewer than 3 results
    SELECT MIN(ed.evo_steps) AS evo_steps
    FROM encounter_data ed
    WHERE ed.evo_steps > (SELECT MIN(evo_steps) FROM encounter_data)
      AND (SELECT tier_count FROM tier_counts WHERE evo_steps = (SELECT MIN(evo_steps) FROM encounter_data)) < 3
),

filtered_encounters AS (
    SELECT ed.*
    FROM encounter_data ed
    INNER JOIN included_tiers it ON ed.evo_steps = it.evo_steps
),

encounter_tiles AS (
    SELECT
        ed.encounter_map,
        ed.area,
        t.x AS tile_x,
        t.y AS tile_y,
        ABS(t.x - {{ player_x }}) + ABS(t.y - {{ player_y }}) AS tile_distance,
        ROW_NUMBER() OVER (
            PARTITION BY ed.encounter_map, ed.area
            ORDER BY ABS(t.x - {{ player_x }}) + ABS(t.y - {{ player_y }})
        ) AS tile_rank
    FROM filtered_encounters ed
    INNER JOIN {{ ref('stg_nav_map_tiles') }} t
        ON t.map_name = ed.nav_map_name
        AND t.tile_type = ed.tile_type
        AND t.walkable = TRUE
    WHERE ed.nav_map_name = '{{ map_name }}'
      AND ed.tile_type IS NOT NULL
),

ranked_results AS (
    SELECT
        COALESCE(ed.nav_map_name = '{{ map_name }}', FALSE) AS found_on_map,
        ed.target_pokemon,
        ed.catch_pokemon,
        ed.evo_steps,
        ed.evolve_via,
        ed.evolve_detail,
        ed.encounter_map,
        ed.area,
        ed.min_level,
        ed.max_level,
        ed.total_probability,
        ed.encounter_method,
        ed.tile_type,
        ed.badges_to_reach,
        ed.route_distance,
        et.tile_x,
        et.tile_y,
        et.tile_distance,
        ROW_NUMBER() OVER (
            ORDER BY
                COALESCE(ed.nav_map_name = '{{ map_name }}', FALSE) DESC,
                ed.evo_steps ASC,
                ed.total_probability DESC,
                ed.max_level DESC,
                ed.route_distance ASC,
                et.tile_distance ASC
        ) AS result_rank
    FROM filtered_encounters ed
    LEFT JOIN encounter_tiles et
        ON ed.encounter_map = et.encounter_map
        AND ed.area = et.area
        AND et.tile_rank = 1
)

SELECT
    catch_pokemon,
    encounter_map
FROM ranked_results
WHERE result_rank <= 3
ORDER BY max_level DESC

{% endmacro %}
