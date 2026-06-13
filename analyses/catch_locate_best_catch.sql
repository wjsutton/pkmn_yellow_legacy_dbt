-- locate_best_catch  (MCP tool)
-- INPUT  : pokemon, badge   (team / keep_pikachu / rival / legendary accepted for a
--          uniform tool signature but do NOT affect a catch location)
-- OUTPUT : where to catch the pokemon (or its pre-evolution), ranked best-first:
--          reachable-now locations by encounter probability, with expected casts.
--
-- For evolved forms it resolves the wild pre-evolution to catch, then evolve.

{% set pokemon     = 'Poliwag' %}
{% set badge       = 'Badge_1' %}

{% set badge_num   = badge.split('_')[1] | int if 'Badge_' in badge else 99 %}

WITH sources AS (
    -- the wild species you actually catch for this target (self if base form)
    SELECT DISTINCT initial_pokemon
    FROM {{ ref('int_pokemon_availability') }}
    WHERE pokemon = '{{ pokemon }}'
),
locations AS (
    SELECT
        '{{ pokemon }}'                                   AS target_pokemon,
        el.pokemon                                        AS catch_species,
        el.map_name,
        el.area,
        el.encounter_method,
        el.required_item,
        el.min_level, el.max_level,
        ROUND(el.total_probability, 3)                    AS encounter_prob,
        ROUND(1.0 / NULLIF(el.total_probability, 0), 1)   AS expected_encounters,
        el.badges_to_reach,
        el.route_distance,
        (el.badges_to_reach <= {{ badge_num - 1 }})       AS reachable_now
    FROM {{ ref('int_encounter_lookup') }} el
    INNER JOIN sources s ON s.initial_pokemon = el.pokemon
)
SELECT *,
    CASE WHEN catch_species <> target_pokemon
         THEN 'Catch ' || catch_species || ' then evolve into ' || target_pokemon
         ELSE 'Wild catch'
    END AS how
FROM locations
ORDER BY reachable_now DESC, encounter_prob DESC, route_distance ASC
