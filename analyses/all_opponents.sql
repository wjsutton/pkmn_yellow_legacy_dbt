SELECT
player_pokemon,
player_pkmn_move,
battle_score
FROM {{ ref('int_battle_outcomes') }}
WHERE game_stage = 'Badge_3'
AND trainer = 'Lt._Surge'
AND battle_score IS NOT NULL
ORDER BY battle_score DESC