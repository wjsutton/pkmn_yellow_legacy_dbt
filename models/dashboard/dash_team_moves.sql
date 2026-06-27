-- dash_team_moves: the moveset each roster member should run per run + game stage,
-- with how each move is acquired (level-up at level X, or TM/HM found at map X).
-- A move appears here if it is a mon's best move against >=1 opponent at that stage.
-- Grain: one row per (run_name, game_stage, pokemon, move)
-- Connect to dash_team_roster / dash_team_battles on (run_name, game_stage, pokemon)
-- and dash_team_catch on (game_stage, pokemon) in Tableau.
{{ config(enabled=true) }}

WITH move_usage AS (
    -- Collapse battles to the distinct moves a mon actually wants at this stage,
    -- counting how many opponents each move is the chosen best answer for.
    SELECT
        b.run_name,
        b.rival_type,
        b.keep_pikachu,
        b.no_legends,
        b.variant_description,
        b.game_stage,
        b.pokemon,
        b.sprite_url,
        b.our_move AS move,
        MIN(b.our_move_origin) AS move_origin,
        MAX(b.requires_single_use_tm) AS is_single_use_tm,
        COUNT(DISTINCT b.trainer_pkmn_id) AS opponents_best_against,
        COUNT(DISTINCT CASE WHEN b.player_victory = 1 THEN b.trainer_pkmn_id END) AS opponents_defeated,
        ROUND(AVG(b.battle_score), 3) AS avg_battle_score
    FROM {{ ref('dash_team_battles_base') }} b
    GROUP BY
        b.run_name, b.rival_type, b.keep_pikachu, b.no_legends, b.variant_description,
        b.game_stage, b.pokemon, b.sprite_url, b.our_move
),

-- One acquisition row per (pokemon, move, origin): level for level-up, location for TM/HM.
acquisition AS (
    SELECT
        pokemon,
        move,
        move_origin,
        MIN(pkmn_level) AS pkmn_level,
        MIN(location_details) AS location_details,
        MIN(move_type) AS move_type
    FROM {{ ref('int_pokemon_movesets') }}
    GROUP BY pokemon, move, move_origin
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['mu.run_name', 'mu.game_stage', 'mu.pokemon', 'mu.move']) }} AS surrogate_key,
    mu.run_name,
    mu.rival_type,
    mu.keep_pikachu,
    mu.no_legends,
    mu.variant_description,
    mu.game_stage,
    mu.pokemon,
    mu.sprite_url,
    mu.move,
    a.move_type,
    mu.move_origin,
    a.pkmn_level AS acquire_level,
    a.location_details AS acquire_location,
    CASE
        WHEN mu.move_origin = 'level-up' AND a.pkmn_level IS NOT NULL
            THEN 'Learn at level ' || a.pkmn_level
        WHEN a.location_details IS NOT NULL
            THEN a.location_details
        ELSE 'Unknown'
    END AS acquisition,
    mu.is_single_use_tm,
    mu.opponents_best_against,
    mu.opponents_defeated,
    mu.avg_battle_score
FROM move_usage mu
LEFT JOIN acquisition a
    ON a.pokemon = mu.pokemon
    AND a.move = mu.move
    AND a.move_origin = mu.move_origin
ORDER BY mu.run_name, mu.game_stage, mu.pokemon, mu.opponents_best_against DESC
