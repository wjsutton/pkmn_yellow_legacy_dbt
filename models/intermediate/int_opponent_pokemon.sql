WITH all_trainer_moves AS (
    -- All trainer sources now have explicit moves
    SELECT
        trainer,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        CAST(notes AS VARCHAR) AS notes,
        pkmn_level,
        move,
        move_number
    FROM {{ ref('stg_trainers_mandatory') }}

    UNION ALL

    SELECT
        trainer,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        CAST(notes AS VARCHAR) AS notes,
        pkmn_level,
        move,
        move_number
    FROM {{ ref('stg_trainers_legendary') }}

    UNION ALL

    SELECT
        trainer,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        CAST(notes AS VARCHAR) AS notes,
        pkmn_level,
        move,
        move_number
    FROM {{ ref('stg_trainers_gym_leaders') }}

    UNION ALL

    SELECT
        trainer,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        CAST(notes AS VARCHAR) AS notes,
        pkmn_level,
        move,
        move_number
    FROM {{ ref('stg_trainers_non_mandatory') }}

    UNION ALL

    SELECT
        trainer,
        pkmn_id,
        nearest_route,
        pokemon,
        game_stage,
        CAST(notes AS VARCHAR) AS notes,
        pkmn_level,
        move,
        move_number
    FROM {{ ref('stg_trainers_postgame') }}
),

trainer_roster AS (
    SELECT
        T.trainer,
        T.game_stage,
        R.game_order,
        T.notes,
        T.pkmn_id,
        S.pokedex,
        T.pokemon,
        T.pkmn_level,
        MAX(CASE WHEN T.move_number = 1 THEN move END) as move_1,
        MAX(CASE WHEN T.move_number = 2 THEN move END) as move_2,
        MAX(CASE WHEN T.move_number = 3 THEN move END) as move_3,
        MAX(CASE WHEN T.move_number = 4 THEN move END) as move_4
    FROM all_trainer_moves as T
    INNER JOIN {{ ref('stg_game_route_order') }} as R ON T.nearest_route = R.map
    INNER JOIN {{ ref('stg_pkmn_stats') }} as S ON T.pokemon = S.pokemon
    WHERE LOWER(T.game_stage) NOT LIKE '%_alt%'
    GROUP BY ALL
)

-- Main output: Complete trainer and pokemon roster with routes
SELECT
    -- Trainer identification
    tr.trainer,
    tr.game_stage,
    tr.game_order,
    tr.notes,

    -- Pokemon details
    tr.pkmn_id,
    tr.pokedex,
    tr.pokemon,
    tr.pkmn_level,

    -- Movesets
    tr.move_1,
    tr.move_2,
    tr.move_3,
    tr.move_4

FROM trainer_roster as tr
ORDER BY game_order
