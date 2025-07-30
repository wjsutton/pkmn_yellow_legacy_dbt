-- Query to find Flareon_Standard_KeepPika_NoLedges team for Badge_3
SELECT 
    run,
    game_stage,
    player_pkmn_id,
    player_pokemon,
    COUNT(*) as move_count
FROM {{ ref('opt_recommended_teams') }}
WHERE run = 'Flareon_Standard_KeepPika_NoLedges'
    AND game_stage = 'Badge_3'
GROUP BY run, game_stage, player_pkmn_id, player_pokemon
ORDER BY player_pokemon