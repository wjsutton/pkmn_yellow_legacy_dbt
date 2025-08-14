
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
    NULL as notes,
    pkmn_level
FROM {{ source('yellow_legacy', 'trainers_mandatory') }} 
