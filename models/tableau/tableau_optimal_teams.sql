SELECT * FROM {{ ref('teams_optimisation') }} 

UNION ALL

SELECT * FROM {{ ref('teams_optimisation_with_pikachu') }} 