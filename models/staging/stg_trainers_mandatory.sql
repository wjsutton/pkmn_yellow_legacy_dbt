
SELECT 
    Trainer as trainer,
    Pkmn_id as pkmn_id,
    Map as location,
    Nearest_Route as nearest_route,
    CASE Pokemon 
            WHEN 'Nidoran_m' THEN 'Nidoran-m'
            WHEN 'Nidoran_f' THEN 'Nidoran-f'
            ELSE Pokemon
    END as pokemon,
    Game_Stage as game_stage,
    NULL as notes,
    Level as level
FROM {{ source('yellow_legacy', 'trainers_mandatory') }} 
