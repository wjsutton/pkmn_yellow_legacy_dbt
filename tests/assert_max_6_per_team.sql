-- Test: Each team has a maximum of 6 pokemon
-- Fails if any run_name + game_stage combination has more than 6 pokemon
SELECT
    run_name,
    game_stage,
    COUNT(*) as team_size
FROM {{ ref('opt_recommended_teams') }}
GROUP BY run_name, game_stage
HAVING COUNT(*) > 6
