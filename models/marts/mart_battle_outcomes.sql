-- mart_battle_outcomes: Who wins in a fight?
-- Calculates battle outcomes for all player vs trainer pokemon matchups.

WITH player_availability AS (
    -- Deduplicate to one row per (pokemon, game_stage).
    -- game_order = earliest catch point (for matchup eligibility).
    -- max_route = latest availability (for maximum TM access).
    SELECT
        pokemon,
        game_stage,
        MIN(earliest_route) AS game_order,
        MAX(earliest_route) AS max_route,
        MAX(level_cap) AS level_cap
    FROM {{ ref('int_pokemon_availability') }}
    GROUP BY pokemon, game_stage
),

player_moves AS (
    -- Player pokemon with their best available move per type.
    -- Within the same type, STAB, type effectiveness, and stat used
    -- are all identical in Gen 1, so highest power*accuracy always wins.
    SELECT
        pa.game_stage,
        pa.game_order,
        pa.max_route,
        'Player_' || pa.pokemon || '_1' AS pkmn_id,
        pa.pokemon,
        pa.level_cap AS pkmn_level,
        ps.type1,
        ps.type2,
        ms.move,
        ms.move_origin,
        COALESCE(ms.move_type, s.type) AS move_type,
        COALESCE(ms.move_power, s.power) AS move_power,
        COALESCE(ms.move_accuracy, s.acc) AS move_acc,
        s.hits_min AS move_hits_min,
        CASE WHEN ms.move_origin = 'single-use-tm' THEN 1 ELSE 0 END AS is_single_use_tm,
        CASE
            WHEN COALESCE(ms.move_type, s.type) = ps.type1 THEN 1.5
            WHEN COALESCE(ms.move_type, s.type) = ps.type2 THEN 1.5
            ELSE 1
        END AS move_stab,
        COALESCE(ms.move_stat_used, physpec.stat_used) AS move_stat,
        ps.speed AS base_speed,
        s.critical_hit_ratio,
        psc.calculated_hp AS hp,
        psc.calculated_attack AS attack,
        psc.calculated_defence AS defence,
        psc.calculated_special AS special,
        psc.calculated_speed AS speed
    FROM player_availability AS pa
    INNER JOIN {{ ref('int_pokemon_movesets') }} AS ms
        ON pa.pokemon = ms.pokemon
    INNER JOIN {{ ref('stg_pkmn_stats') }} AS ps
        ON pa.pokemon = ps.pokemon
    INNER JOIN {{ ref('int_pokemon_stats') }} AS psc
        ON pa.pokemon = psc.pokemon AND pa.level_cap = psc.pkmn_level
    LEFT JOIN {{ ref('stg_moves_stats') }} AS s
        ON ms.move = s.move
    LEFT JOIN {{ ref('stg_moves_phys_spec') }} AS physpec
        ON COALESCE(ms.move_type, s.type) = physpec.type
    WHERE (
        (ms.pkmn_level <= pa.level_cap AND ms.move_origin = 'level-up')
        OR (ms.route_order <= pa.max_route AND ms.move_origin <> 'level-up')
    )
    AND COALESCE(ms.move_power, s.power) <> 'N/A'
    AND COALESCE(ms.move_power, s.power) IS NOT NULL
    AND COALESCE(ms.move_power, s.power) NOT IN ('Copy', 'Set', 'Var Dmg')
    AND COALESCE(ms.move_accuracy, s.acc) <> 'N/A'
    QUALIFY
        COALESCE(ms.move_power, s.power) = 'KO'
        OR ms.move IN ('Sonicboom', 'Dragon Rage', 'Super Fang', 'Psywave', 'Seismic Toss', 'Night Shade')
        OR ROW_NUMBER() OVER(
            PARTITION BY pa.game_stage, pa.pokemon, COALESCE(ms.move_type, s.type),
                CASE WHEN ms.move_origin = 'single-use-tm' THEN 1 ELSE 0 END
            ORDER BY
                TRY_CAST(COALESCE(ms.move_power, s.power) AS DOUBLE)
                * COALESCE(TRY_CAST(COALESCE(ms.move_accuracy, s.acc) AS DOUBLE), 1.0)
                / (CASE WHEN ms.move IN ('Solarbeam', 'Razor Wind', 'Skull Bash', 'Hyper Beam') THEN 2 ELSE 1 END)
                DESC
        ) = 1
),

trainer_moves AS (
    -- Trainer pokemon with their best available move per type.
    -- Same pre-filter logic as player_moves: within the same type,
    -- STAB/effectiveness/stat are identical in Gen 1, so highest
    -- power*accuracy always wins. KO and fixed-damage moves always kept.
    SELECT
        unpvt.trainer,
        unpvt.game_stage,
        unpvt.game_order,
        unpvt.pkmn_id,
        unpvt.pokemon,
        unpvt.pkmn_level,
        ps.type1,
        ps.type2,
        unpvt.move,
        ms.type AS move_type,
        ms.power AS move_power,
        ms.acc AS move_acc,
        ms.hits_min AS move_hits_min,
        CASE
            WHEN ms.type = ps.type1 THEN 1.5
            WHEN ms.type = ps.type2 THEN 1.5
            ELSE 1
        END AS move_stab,
        physpec.stat_used AS move_stat,
        ps.speed AS base_speed,
        ms.critical_hit_ratio,
        psc.calculated_hp AS hp,
        psc.calculated_attack AS attack,
        psc.calculated_defence AS defence,
        psc.calculated_special AS special,
        psc.calculated_speed AS speed
    FROM {{ ref('int_opponent_pokemon') }}
    UNPIVOT (move FOR move_slot IN (move_1, move_2, move_3, move_4)) AS unpvt
    INNER JOIN {{ ref('stg_moves_stats') }} AS ms ON unpvt.move = ms.move
    INNER JOIN {{ ref('stg_pkmn_stats') }} AS ps ON unpvt.pokemon = ps.pokemon
    INNER JOIN {{ ref('int_pokemon_stats') }} AS psc
        ON unpvt.pokemon = psc.pokemon AND unpvt.pkmn_level = psc.pkmn_level
    LEFT JOIN {{ ref('stg_moves_phys_spec') }} AS physpec ON ms.type = physpec.type
    WHERE unpvt.move IS NOT NULL
        AND ms.power <> 'N/A'
        AND ms.power IS NOT NULL
        AND ms.power NOT IN ('Copy', 'Set', 'Var Dmg')
        AND ms.acc <> 'N/A'
    QUALIFY
        ms.power = 'KO'
        OR unpvt.move IN ('Sonicboom', 'Dragon Rage', 'Super Fang', 'Psywave', 'Seismic Toss', 'Night Shade')
        OR ROW_NUMBER() OVER(
            PARTITION BY unpvt.pkmn_id, ms.type
            ORDER BY
                TRY_CAST(ms.power AS DOUBLE)
                * COALESCE(TRY_CAST(ms.acc AS DOUBLE), 1.0)
                / (CASE WHEN unpvt.move IN ('Solarbeam', 'Razor Wind', 'Skull Bash', 'Hyper Beam') THEN 2 ELSE 1 END)
                DESC
        ) = 1
),

type_effectiveness_lookup AS (
    SELECT
        attacking_type,
        defending_type AS type1,
        CAST(NULL AS VARCHAR) AS type2,
        damage_modifier AS total_effectiveness
    FROM {{ ref('stg_moves_type_effectiveness') }}

    UNION ALL

    SELECT
        te1.attacking_type,
        te1.defending_type AS type1,
        te2.defending_type AS type2,
        te1.damage_modifier * te2.damage_modifier AS total_effectiveness
    FROM {{ ref('stg_moves_type_effectiveness') }} AS te1
    INNER JOIN {{ ref('stg_moves_type_effectiveness') }} AS te2
        ON te1.attacking_type = te2.attacking_type
        AND te1.defending_type <> te2.defending_type
),

-- Distinct pokemon on each side (no move detail) for damage cross-joins
trainer_pokemon AS (
    SELECT DISTINCT
        pkmn_id, trainer, pokemon, pkmn_level, game_stage, game_order,
        type1, type2, hp, attack, defence, special, speed
    FROM trainer_moves
),

player_pokemon AS (
    SELECT DISTINCT
        pkmn_id, pokemon, pkmn_level, game_stage, game_order, max_route,
        type1, type2, hp, attack, defence, special, speed
    FROM player_moves
),

-- Player attacking trainer: cross-join with pre-computed stats
player_matchups AS (
    SELECT
        p.game_stage,
        p.pkmn_id AS attacker_pkmn_id,
        p.pokemon AS attacker_pokemon,
        p.pkmn_level AS attacker_level,
        p.speed AS attacker_speed,
        td.speed AS defender_speed,
        td.hp AS defender_hp,
        p.move,
        p.move_origin,
        p.move_acc,
        p.move_stab,
        p.move_power,
        p.move_hits_min,
        p.is_single_use_tm,
        p.base_speed,
        p.critical_hit_ratio,
        td.pkmn_id AS defender_pkmn_id,
        td.trainer AS defender,
        td.pokemon AS defender_pokemon,
        td.pkmn_level AS defender_level,
        tel.total_effectiveness AS attacker_move_type_effectiveness,
        CASE WHEN p.move_stat = 'Attack' THEN td.defence ELSE td.special END AS defender_stat,
        CASE WHEN p.move_stat = 'Attack' THEN p.attack ELSE p.special END AS attacker_stat
    FROM player_moves AS p
    INNER JOIN trainer_pokemon AS td
        ON p.game_stage = td.game_stage
        AND p.game_order <= td.game_order
    INNER JOIN type_effectiveness_lookup AS tel
        ON p.move_type = tel.attacking_type
        AND td.type1 = tel.type1
        AND (td.type2 = tel.type2 OR (tel.type2 IS NULL AND td.type2 IS NULL))
),

player_damage_raw AS (
    SELECT
        game_stage, attacker_pkmn_id, attacker_pokemon, attacker_level,
        attacker_speed, defender_speed, defender_hp,
        move, move_origin, is_single_use_tm,
        defender_pkmn_id, defender, defender_pokemon, defender_level,
        CASE
            WHEN move_power = 'KO' AND attacker_speed <= defender_speed THEN 0
            ELSE
                {{ calculate_damage_rby('defender_stat', 'defender_hp', 'attacker_stat', 'attacker_level', 'move', 'move_acc', 'attacker_move_type_effectiveness', 'move_stab', 'move_power', 'move_hits_min') }}
                * {{ calculate_crit_multiplier_rby('base_speed', 'critical_hit_ratio', 'attacker_level', 'move', 'move_power') }}
        END AS damage
    FROM player_matchups
),

player_damage AS (
    SELECT
        game_stage, attacker_pkmn_id, attacker_pokemon, attacker_level,
        attacker_speed, defender_speed,
        move, move_origin, is_single_use_tm,
        defender_pkmn_id, defender, defender_pokemon, defender_level,
        CASE
            WHEN damage = 0 THEN NULL
            WHEN move = 'Hyper Beam' AND damage < defender_hp THEN (defender_hp / damage) * 2
            ELSE defender_hp / damage
        END AS attempts_to_ko
    FROM player_damage_raw
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY attacker_pkmn_id, defender_pkmn_id
        ORDER BY CASE
            WHEN damage = 0 THEN NULL
            WHEN move = 'Hyper Beam' AND damage < defender_hp THEN (defender_hp / damage) * 2
            ELSE defender_hp / damage
        END ASC
    ) <= 4
),

-- Trainer attacking player: cross-join with pre-computed stats
trainer_matchups AS (
    SELECT
        t.pkmn_id AS attacker_pkmn_id,
        pd.pkmn_id AS defender_pkmn_id,
        t.move,
        t.move_acc,
        t.move_stab,
        t.move_power,
        t.move_hits_min,
        t.pkmn_level AS attacker_level,
        t.speed AS attacker_speed,
        pd.speed AS defender_speed,
        t.base_speed,
        t.critical_hit_ratio,
        pd.hp AS defender_hp,
        tel.total_effectiveness AS attacker_move_type_effectiveness,
        CASE WHEN t.move_stat = 'Attack' THEN pd.defence ELSE pd.special END AS defender_stat,
        CASE WHEN t.move_stat = 'Attack' THEN t.attack ELSE t.special END AS attacker_stat,
        CASE WHEN t.move_power = 'KO' THEN TRUE ELSE FALSE END AS is_ohko_move,
        TRY_CAST(t.move_acc AS DOUBLE) AS move_accuracy
    FROM trainer_moves AS t
    INNER JOIN player_pokemon AS pd
        ON t.game_stage = pd.game_stage
        AND t.game_order <= pd.max_route
    INNER JOIN type_effectiveness_lookup AS tel
        ON t.move_type = tel.attacking_type
        AND pd.type1 = tel.type1
        AND (pd.type2 = tel.type2 OR (tel.type2 IS NULL AND pd.type2 IS NULL))
),

trainer_damage_raw AS (
    SELECT
        attacker_pkmn_id, defender_pkmn_id,
        move, is_ohko_move, move_accuracy, defender_hp,
        CASE
            WHEN is_ohko_move AND attacker_speed <= defender_speed THEN 0
            ELSE
                {{ calculate_damage_rby('defender_stat', 'defender_hp', 'attacker_stat', 'attacker_level', 'move', 'move_acc', 'attacker_move_type_effectiveness', 'move_stab', 'move_power', 'move_hits_min') }}
                * {{ calculate_crit_multiplier_rby('base_speed', 'critical_hit_ratio', 'attacker_level', 'move', 'move_power') }}
        END AS damage
    FROM trainer_matchups
),

trainer_damage AS (
    -- Keep only the trainer's best move against each specific player pokemon.
    -- This ensures e.g. Raichu uses Surf (4x effective) vs Geodude,
    -- not Body Slam, because the trainer picks the strongest option.
    SELECT
        attacker_pkmn_id, defender_pkmn_id,
        move, is_ohko_move, move_accuracy,
        CASE
            WHEN move = 'Hyper Beam' AND damage < defender_hp THEN (defender_hp / damage) * 2
            ELSE defender_hp / damage
        END AS attempts_to_ko
    FROM trainer_damage_raw
    WHERE damage > 0
    QUALIFY ROW_NUMBER() OVER(
        PARTITION BY attacker_pkmn_id, defender_pkmn_id
        ORDER BY
            CASE
                WHEN move = 'Hyper Beam' AND damage < defender_hp THEN (defender_hp / damage) * 2
                ELSE defender_hp / damage
            END ASC
    ) = 1
),

mini_bosses AS (
    SELECT DISTINCT trainer
    FROM {{ ref('stg_trainers_gym_leaders') }}
),

-- Fly/Dig are 1-turn moves (opponent misses during dodge) UNLESS the
-- opponent uses Swift, which hits through the dodge turn. When Swift is
-- the opposing move, Fly/Dig becomes a 2-turn move for the user.
battle_pairs AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['P.attacker_pkmn_id', 'P.defender_pkmn_id', 'P.move', 'T.move', 'P.move_origin']) }} AS matchup_id,
        P.game_stage,
        P.defender AS trainer,
        CASE WHEN MB.trainer IS NOT NULL THEN 1 ELSE 0 END AS is_mini_boss,
        P.attacker_pkmn_id AS player_pkmn_id,
        P.attacker_pokemon AS player_pokemon,
        P.attacker_level AS player_pkmn_level,
        P.move AS player_pkmn_move,
        P.move_origin AS player_pkmn_move_origin,
        P.is_single_use_tm AS player_move_single_use_tm,
        P.defender_pkmn_id AS trainer_pkmn_id,
        P.defender_pokemon AS trainer_pokemon,
        P.defender_level AS trainer_pkmn_level,
        T.move AS trainer_pkmn_move,
        P.defender_speed AS trainer_speed,
        P.attacker_speed AS player_speed,
        T.is_ohko_move,
        T.move_accuracy,
        CASE
            WHEN P.move IN ('Fly', 'Dig') AND T.move = 'Swift' THEN P.attempts_to_ko * 2
            ELSE P.attempts_to_ko
        END AS player_attempts_to_ko,
        CASE
            WHEN T.move IN ('Fly', 'Dig') AND P.move = 'Swift' THEN T.attempts_to_ko * 2
            ELSE T.attempts_to_ko
        END AS trainer_attempts_to_ko
    FROM player_damage AS P
    INNER JOIN trainer_damage AS T
        ON T.defender_pkmn_id = P.attacker_pkmn_id
        AND T.attacker_pkmn_id = P.defender_pkmn_id
    LEFT JOIN mini_bosses AS MB
        ON P.defender = MB.trainer
)

, final AS (
    SELECT
        matchup_id,
        game_stage,
        'Player' AS player,
        trainer,
        is_mini_boss,
        player_pkmn_id,
        player_pokemon,
        player_pkmn_level,
        player_pkmn_move,
        player_pkmn_move_origin,
        player_move_single_use_tm,
        trainer_pkmn_id,
        trainer_pokemon,
        trainer_pkmn_level,
        trainer_pkmn_move,
        trainer_speed,
        player_speed,
        player_attempts_to_ko,
        trainer_attempts_to_ko,
        {{ calculate_battle_outcome() }} AS battle_score
    FROM battle_pairs
)

SELECT
    *,
    CASE WHEN battle_score > 0 THEN 1 ELSE 0 END AS player_victory
FROM final
