WITH pokemon_totals AS (
    SELECT 
        game_stage,
        player_pkmn_id,
        SUM(battle_score) as total_battle_score,
        COUNT(*) as total_battles,
        AVG(battle_score) as avg_battle_score
    FROM {{ ref('int_team_optimization') }}
    GROUP BY game_stage, player_pkmn_id
),

ranked_pokemon AS (
    SELECT 
        game_stage,
        player_pkmn_id,
        total_battle_score,
        total_battles,
        avg_battle_score,
        ROW_NUMBER() OVER (
            PARTITION BY game_stage 
            ORDER BY total_battle_score DESC
        ) as team_rank
    FROM pokemon_totals
)

SELECT 
    game_stage,
    player_pkmn_id,
    total_battle_score,
    total_battles,
    avg_battle_score,
    team_rank
FROM ranked_pokemon
WHERE team_rank <= 6
ORDER BY game_stage, team_rank