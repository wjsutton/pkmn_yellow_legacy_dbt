WITH all_trainers as (

SELECT DISTINCT
    trainer,
    game_stage,
    notes
FROM {{ ref('int_trainers_all') }} 

)

SELECT 
    'Jolteon_Standard_Ledges' as run,
    trainer,
    game_stage
FROM all_trainers
WHERE notes IN ('Jolteon Version','Legendary') OR notes IS NULL

UNION ALL 

SELECT 
    'Flareon_Standard_Ledges' as run,
    trainer,
    game_stage
FROM all_trainers
WHERE (notes IN ('Flareon Version','Legendary') OR notes IS NULL)
AND trainer NOT IN ('Rival_2')

UNION ALL 

SELECT 
    'Vaporeon_Standard_Ledges' as run,
    trainer,
    game_stage
FROM all_trainers
WHERE (notes IN ('Vaporeon Version','Legendary') OR notes IS NULL)
AND trainer NOT IN ('Rival_1','Rival_2')

UNION ALL 

SELECT 
    'Jolteon_Standard_NoLedges' as run,
    trainer,
    game_stage
FROM all_trainers
WHERE notes IN ('Jolteon Version') OR notes IS NULL

UNION ALL 

SELECT 
    'Flareon_Standard_NoLedges' as run,
    trainer,
    game_stage
FROM all_trainers
WHERE (notes IN ('Flareon Version') OR notes IS NULL)
AND trainer NOT IN ('Rival_2')

UNION ALL 

SELECT 
    'Vaporeon_Standard_NoLedges' as run,
    trainer,
    game_stage
FROM all_trainers
WHERE (notes IN ('Vaporeon Version') OR notes IS NULL)
AND trainer NOT IN ('Rival_1','Rival_2')