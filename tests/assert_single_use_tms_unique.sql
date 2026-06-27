-- Test: Single-use TMs can only be assigned once per team (per run_name + game_stage)
-- Fails if any single-use TM is assigned to multiple pokemon on the same team
SELECT
    RT.run_name,
    RT.game_stage,
    RT.assigned_tm_move,
    COUNT(*) as times_assigned
FROM {{ ref('mart_recommended_teams') }} RT
INNER JOIN {{ ref('stg_moves_tmhm_locations') }} TL
    ON RT.assigned_tm_move = TL.move
WHERE RT.assigned_tm_move <> 'None'
    AND TL.earliest_nearest_route <> TL.repurchase_route
GROUP BY RT.run_name, RT.game_stage, RT.assigned_tm_move
HAVING COUNT(*) > 1
