-- dash_team_battles_base: full per-(member x opponent) matchup with each member's best
-- move, run-variant filtered. Ephemeral (no table) -- shared by dash_team_battles
-- (reduced to the single best member per opponent) and dash_team_moves (per-member movesets).
{{ config(enabled=true, materialized='ephemeral') }}

WITH team_members AS (
    -- roster is now the full candidate pool; restrict to the precomputed team picks
    -- and carry the strategy flags so downstream can split damage vs ease.
    SELECT DISTINCT run_name, game_stage, pokemon, on_damage_team, on_ease_team
    FROM {{ ref('dash_team_roster') }}
    WHERE on_damage_team = 1 OR on_ease_team = 1
),

run_variants AS (
    {{ generate_run_variants(ref('mart_battle_outcomes')) }}
),

-- Best move per (our pokemon, opponent pokemon instance)
best_moves AS (
    SELECT
        bo.game_stage,
        bo.player_pokemon,
        bo.trainer,
        bo.is_mini_boss,
        bo.trainer_pkmn_id,
        bo.trainer_pokemon,
        bo.trainer_pkmn_level,
        bo.player_pkmn_move,
        bo.player_pkmn_move_origin,
        bo.player_move_single_use_tm,
        bo.player_attempts_to_ko,
        bo.trainer_pkmn_move,
        bo.trainer_attempts_to_ko,
        bo.battle_score,
        bo.player_victory
    FROM {{ ref('mart_battle_outcomes') }} bo
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY bo.player_pokemon, bo.trainer_pkmn_id
        ORDER BY bo.battle_score DESC
    ) = 1
),

stage_costs AS (
    SELECT pokemon, game_stage, fresh_exp_cost
    FROM {{ ref('mart_stage_pokemon_costs') }}
)

SELECT
    tm.run_name,
    rv.rival_type,
    rv.keep_pikachu,
    rv.no_legends,
    {{ generate_variant_description('rv.rival_type', 'rv.keep_pikachu', 'rv.no_legends') }} AS variant_description,
    tm.game_stage,
    tm.pokemon,
    tm.on_damage_team,
    tm.on_ease_team,
    {{ pokemon_sprite_url('tm.pokemon') }} AS sprite_url,
    bm.trainer,
    {{ trainer_sprite_url('bm.trainer') }} AS trainer_sprite_url,
    bm.is_mini_boss,
    bm.trainer_pkmn_id,
    bm.trainer_pokemon,
    {{ pokemon_sprite_url('bm.trainer_pokemon') }} AS opponent_sprite_url,
    bm.trainer_pkmn_level,
    bm.player_pkmn_move AS our_move,
    bm.player_pkmn_move_origin AS our_move_origin,
    bm.player_move_single_use_tm AS requires_single_use_tm,
    bm.player_attempts_to_ko AS our_turns_to_ko,
    bm.trainer_pkmn_move AS opponent_move,
    bm.trainer_attempts_to_ko AS opponent_turns_to_ko,
    bm.battle_score,
    bm.player_victory,
    sc.fresh_exp_cost AS exp_to_cap
FROM team_members tm
INNER JOIN run_variants rv
    ON rv.run_name = tm.run_name
    AND rv.game_stage = tm.game_stage
INNER JOIN best_moves bm
    ON bm.game_stage = tm.game_stage
    AND bm.player_pokemon = tm.pokemon
LEFT JOIN stage_costs sc
    ON sc.pokemon = tm.pokemon
    AND sc.game_stage = tm.game_stage
WHERE NOT (bm.trainer LIKE rv.exclude_rival_patterns[1])
  AND NOT (bm.trainer LIKE rv.exclude_rival_patterns[2])
  AND NOT list_contains(rv.exclude_trainers, bm.trainer)
