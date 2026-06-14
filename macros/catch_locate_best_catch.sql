{% macro catch_locate_best_catch(pokemon='Poliwag', badge='Badge_1', team=['Pikachu'], keep_pikachu='KeepPikachu', rival='Flareon', legendary='NoLedges') %}
{#
    catch_locate_best_catch — where to catch a pokemon (or its pre-evolution).

    Built on the catch semantic view tables (models/semantic/_catch_semantic.yml):
        int_pokemon_availability + int_encounter_lookup.

    Ranked best-first: reachable-now locations by encounter probability, with expected
    casts. For evolved forms it resolves the wild pre-evolution to catch, then evolve.

    Args:
        pokemon   target species, e.g. 'Poliwag' (or an evolved form like 'Nidoking')
        badge     current game stage, e.g. 'Badge_1' .. 'Badge_8'
        team, keep_pikachu, rival, legendary  accepted for a uniform tool signature
                  but do NOT affect a catch location.

    Returns: target_pokemon, catch_species, map_name, area, encounter_method,
             required_item, min_level, max_level, encounter_prob, expected_encounters,
             pct_per_step, expected_steps_to_meet, catch_rate, catch_difficulty,
             catch_cost_exp, badges_to_reach, route_distance, reachable_now, how

    encounter_prob = how OFTEN you meet it (rarity); pct_per_step / expected_steps_to_meet
    fold in the per-map encounter rate byte (rate/256 per step); catch_rate / catch_difficulty =
    how hard it is to actually catch once met (Gen-1 0-255 byte, higher = easier).
    catch_cost_exp = EXP-equivalent effort to obtain one here (meet AND catch).
#}
{% set badge_num = badge.split('_')[1] | int if 'Badge_' in badge else 99 %}

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
        el.pct_per_step,
        el.expected_steps_to_meet,
        el.catch_rate,
        el.catch_difficulty,
        -- EXP-equivalent effort to actually obtain one here (meet AND catch).
        {{ calculate_catch_cost_exp('el.total_probability', 'el.catch_rate', 'el.avg_wild_exp') }} AS catch_cost_exp,
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

{% endmacro %}
