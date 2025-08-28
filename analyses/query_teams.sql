-- Query to find Flareon_Standard_KeepPika_NoLedges team for Badge_3
SELECT 
    run_name,
    game_stage,
    player_pkmn_id,
    player_pokemon,
    COUNT(*) as move_count
FROM {{ ref('opt_recommended_teams') }}
WHERE run_name = 'Flareon_KeepPikachu_Ledges'
    AND game_stage = 'Badge_3'
GROUP BY ALL
ORDER BY player_pokemon