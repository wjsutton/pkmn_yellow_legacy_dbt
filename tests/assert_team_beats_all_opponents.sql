-- Test: Every recommended team must have at least one member that can beat
-- each opponent pokemon. Returns "bad matchups" where no team member wins.
-- {{ config(severity='warn') }}
WITH team_vs_opponents AS (
    SELECT
        RT.run_name,
        RT.game_stage,
        BO.trainer,
        BO.trainer_pkmn_id,
        BO.trainer_pokemon,
        BO.player_victory
    FROM {{ ref('opt_recommended_teams') }} RT
    INNER JOIN {{ ref('int_battle_outcomes') }} BO
        ON RT.game_stage = BO.game_stage
        AND RT.player_pkmn_id = BO.player_pkmn_id
    WHERE
        -- Exclude trainers matching rival patterns for this variant
        NOT EXISTS (
            SELECT 1 FROM UNNEST(RT.exclude_rival_patterns) AS t(pattern)
            WHERE BO.trainer LIKE t.pattern
        )
        -- Exclude trainers by exact name for this variant
        AND NOT list_contains(RT.exclude_trainers, BO.trainer)
)

SELECT
    run_name,
    game_stage,
    trainer,
    trainer_pkmn_id,
    trainer_pokemon,
    MAX(player_victory) AS best_victory
FROM team_vs_opponents
GROUP BY run_name, game_stage, trainer, trainer_pkmn_id, trainer_pokemon
HAVING MAX(player_victory) = 0
