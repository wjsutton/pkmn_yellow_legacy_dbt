{% macro find_encounter_zone(pokemon, map_name, player_x, player_y, badge_count=0, area_filter=none) %}
{#
  Find encounter zones for a specific Pokemon relative to player position.
  Supports all encounter types (Grass, Surf, Fishing, Gift, Trade, etc.)

  Parameters:
    pokemon      - Pokemon name to search for
    map_name     - Current map in UPPER_SNAKE_CASE (e.g. 'ROUTE_1')
    player_x     - Current X coordinate
    player_y     - Current Y coordinate
    badge_count  - Number of badges collected. Filters by:
                   1) Can the player REACH the location? (badges_to_reach)
                   2) Can the player USE the encounter method? (required_badge_count)
    area_filter  - Optional: limit to specific area type (e.g. 'Grass', 'Surf')

  Usage:
    {{ find_encounter_zone('Pidgey', 'ROUTE_1', 5, 10) }}
    {{ find_encounter_zone('Magikarp', 'VIRIDIAN_CITY', 5, 5, badge_count=0, area_filter='OldRod') }}
    {{ find_encounter_zone('Tentacool', 'FUCHSIA_CITY', 5, 5, badge_count=5) }}
#}

WITH encounter_data AS (
    SELECT
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
    FROM {{ ref('int_encounter_lookup') }} el
    WHERE LOWER(el.pokemon) = LOWER('{{ pokemon }}')
      AND el.badges_to_reach <= {{ badge_count }}
      AND el.required_badge_count <= {{ badge_count }}
      {% if area_filter is not none %}
      AND el.area = '{{ area_filter }}'
      {% endif %}
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
    FROM encounter_data ed
    INNER JOIN {{ ref('stg_nav_map_tiles') }} t
        ON t.map_name = ed.nav_map_name
        AND t.tile_type = ed.tile_type
        AND t.walkable = TRUE
    WHERE ed.nav_map_name = '{{ map_name }}'
      AND ed.tile_type IS NOT NULL
)

SELECT
    COALESCE(ed.nav_map_name = '{{ map_name }}', FALSE) AS found_on_map,
    ed.pokemon,
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
    et.tile_distance
FROM encounter_data ed
LEFT JOIN encounter_tiles et
    ON ed.encounter_map = et.encounter_map
    AND ed.area = et.area
    AND et.tile_rank = 1
ORDER BY
    found_on_map DESC,
    ed.max_level DESC,
    ed.total_probability DESC,
    ed.route_distance ASC,
    et.tile_distance ASC

{% endmacro %}
