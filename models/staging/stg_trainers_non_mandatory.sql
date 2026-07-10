
WITH CTE AS (

    SELECT
        trainer,
        pkmn_id,
        map as location,
        nearest_route,
        CASE pokemon
            WHEN 'Nidoran_m' THEN 'Nidoran-m'
            WHEN 'Nidoran_f' THEN 'Nidoran-f'
            ELSE pokemon
        END as pokemon,
        game_stage,
        notes,
        pkmn_level,
        moves as move
    FROM {{ ref('trainers_non_mandatory') }}
    WHERE moves IS NOT NULL

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['pkmn_id', 'move']) }} as id,
    trainer,
    pkmn_id,
    location,
    nearest_route,
    pokemon,
    game_stage,
    notes,
    pkmn_level,
    move,
    ROW_NUMBER() OVER (PARTITION BY pkmn_id ORDER BY move) AS move_number
FROM CTE
QUALIFY ROW_NUMBER() OVER(PARTITION BY pkmn_id ORDER BY move) <= 4
