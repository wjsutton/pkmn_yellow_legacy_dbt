-- dash_team_battles: the single best lineup member to beat each opponent, split by strategy.
-- strategy = 'damage' -> best member of the damage team; 'ease' -> best member of the ease team.
-- One row per opponent per strategy (highest battle score, then fastest KO).
-- Grain: one row per (run_name, game_stage, strategy, trainer_pkmn_id)
-- Connect to dash_team_roster on (run_name, game_stage, pokemon) in Tableau; filter [strategy].
{{ config(enabled=true) }}

-- Tag each base row with the strategy team(s) the member belongs to (a mon on both teams
-- appears under both strategies).
WITH tagged AS (
    SELECT 'damage' AS strategy, *
    FROM {{ ref('dash_team_battles_base') }}
    WHERE on_damage_team = 1
    UNION ALL
    SELECT 'ease' AS strategy, *
    FROM {{ ref('dash_team_battles_base') }}
    WHERE on_ease_team = 1
),

best_member AS (
    SELECT *
    FROM tagged
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY run_name, game_stage, strategy, trainer_pkmn_id
        ORDER BY battle_score DESC, our_turns_to_ko ASC, pokemon ASC
    ) = 1
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['run_name', 'game_stage', 'strategy', 'trainer_pkmn_id']) }} AS surrogate_key,
    *
FROM best_member
ORDER BY run_name, game_stage, strategy, trainer, battle_score DESC
