-- dash_team_catch: where to catch each roster member (or its pre-evolution) per game stage.
-- Run-independent (a catch location does not depend on the run) -- connect to
-- dash_team_roster on (game_stage, pokemon) in Tableau and the run filter propagates.
-- Grain: one row per (game_stage, target_pokemon, catch_species, map_name, area)
{{ config(enabled=true) }}

WITH targets AS (
    -- roster is now the full candidate pool; restrict to the precomputed team picks
    SELECT DISTINCT game_stage, pokemon AS target_pokemon
    FROM {{ ref('dash_team_roster') }}
    WHERE on_damage_team = 1 OR on_ease_team = 1
),

-- The wild species actually caught for each target (self if already a base form)
sources AS (
    SELECT DISTINCT pokemon AS target_pokemon, initial_pokemon
    FROM {{ ref('int_pokemon_availability') }}
    WHERE availability_type = 'Catchable'
),

locations AS (
    SELECT
        t.game_stage,
        t.target_pokemon,
        {{ pokemon_sprite_url('t.target_pokemon') }} AS sprite_url,
        el.pokemon AS catch_species,
        {{ pokemon_sprite_url('el.pokemon') }} AS catch_sprite_url,
        el.map_name,
        el.nav_map_name,
        el.area,
        el.encounter_method,
        el.tile_type,
        el.required_item,
        el.min_level,
        el.max_level,
        ROUND(el.total_probability, 3) AS encounter_prob,
        el.expected_steps_to_meet,
        el.catch_rate,
        el.catch_difficulty,
        el.badges_to_reach,
        el.route_distance,
        CASE
            WHEN t.game_stage LIKE 'Badge_%'
                THEN el.badges_to_reach <= CAST(REPLACE(t.game_stage, 'Badge_', '') AS INT) - 1
            ELSE el.badges_to_reach <= 8
        END AS reachable_now,
        CASE
            WHEN el.pokemon <> t.target_pokemon
                THEN 'Catch ' || el.pokemon || ' then evolve into ' || t.target_pokemon
            ELSE 'Wild catch'
        END AS how
    FROM targets t
    INNER JOIN sources s
        ON s.target_pokemon = t.target_pokemon
    INNER JOIN {{ ref('int_encounter_lookup') }} el
        ON el.pokemon = s.initial_pokemon
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['game_stage', 'target_pokemon', 'catch_species', 'map_name', 'area']) }} AS surrogate_key,
    *
FROM locations
-- only locations actually reachable by this game stage (drop "catchable later" rows)
WHERE reachable_now
ORDER BY game_stage, target_pokemon, encounter_prob DESC
