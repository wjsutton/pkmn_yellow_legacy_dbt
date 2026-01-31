-- int_battle_outcomes: Who wins in a fight?
-- Absorbs int_battle_matchups as CTEs, uses renamed model refs

-- === Battle Matchups (formerly int_battle_matchups) ===
WITH player_pokemon_with_moves AS (
    SELECT
        'Player' AS trainer,
        pa.game_stage,
        pa.earliest_route AS game_order,
        pa.pokemon,
        pa.level_cap AS pkmn_level,
        ms.move,
        ms.move_origin,
        ms.move_type,
        ms.move_power,
        ms.move_accuracy,
        ms.move_stat_used,
        CASE WHEN ms.move_origin = 'single-use-tm' THEN 1 ELSE 0 END as is_single_use_tm,
        'Player_' || pa.pokemon || '_1' AS pkmn_id
    FROM {{ ref('int_pokemon_availability') }} AS pa
    INNER JOIN {{ ref('int_pokemon_movesets') }} AS ms
        ON pa.pokemon = ms.pokemon
    WHERE (
        (ms.pkmn_level <= pa.level_cap AND ms.move_origin = 'level-up')
        OR (ms.route_order <= pa.earliest_route AND ms.move_origin <> 'level-up')
    )
    AND ms.move_power <> 'N/A'
),

trainer_pokemon_with_moves AS (
    SELECT
        trainer,
        game_stage,
        game_order,
        pokemon,
        pkmn_level,
        unpvt.move,
        'trainer' AS move_origin,
        ms.type AS move_type,
        ms.power AS move_power,
        ms.acc AS move_accuracy,
        physpec.stat_used AS move_stat_used,
        0 AS is_single_use_tm,
        pkmn_id
    FROM {{ ref('int_opponent_pokemon') }}
    UNPIVOT (move FOR move_slot IN (move_1, move_2, move_3, move_4)) AS unpvt
    INNER JOIN {{ ref('stg_moves_stats') }} AS ms ON unpvt.move = ms.move
    LEFT JOIN {{ ref('stg_moves_phys_spec') }} AS physpec ON ms.type = physpec.type
    WHERE
        unpvt.move IS NOT null
        AND ms.power <> 'N/A'
        AND ms.power IS NOT null
        AND ms.power NOT IN ('Copy', 'Set', 'Var Dmg')
),

player_and_trainer_pokemon_moves AS (
    SELECT * FROM player_pokemon_with_moves
    UNION ALL
    SELECT * FROM trainer_pokemon_with_moves
),

all_pokemon_with_stats AS (
    SELECT
        t.trainer,
        t.game_stage,
        t.game_order,
        t.pkmn_id,
        t.pokemon,
        t.pkmn_level,
        ps.type1,
        ps.type2,
        t.move,
        t.move_origin,
        s.hits_min AS move_hits_min,
        s.critical_hit_ratio,
        t.is_single_use_tm,
        psc.calculated_hp AS hp,
        psc.calculated_attack AS attack,
        psc.calculated_defence AS defence,
        psc.calculated_special AS special,
        psc.calculated_speed AS speed,
        CASE WHEN t.trainer = 'Player' THEN 1 ELSE 0 END AS player,
        COALESCE(t.move_type, s.type) AS move_type,
        CASE
            WHEN COALESCE(t.move_type, s.type) = ps.type1 THEN 1.5
            WHEN COALESCE(t.move_type, s.type) = ps.type2 THEN 1.5
            ELSE 1
        END AS move_stab,
        COALESCE(t.move_stat_used, physpec.stat_used) AS move_stat,
        COALESCE(t.move_power, s.power) AS move_power,
        COALESCE(t.move_accuracy, s.acc) AS move_acc
    FROM player_and_trainer_pokemon_moves AS t
    INNER JOIN {{ ref('stg_pkmn_stats') }} AS ps ON t.pokemon = ps.pokemon
    INNER JOIN {{ ref('int_pokemon_stats') }} AS psc
        ON ps.pokemon = psc.pokemon AND t.pkmn_level = psc.pkmn_level
    LEFT JOIN {{ ref('stg_moves_stats') }} AS s ON t.move = s.move
    LEFT JOIN {{ ref('stg_moves_phys_spec') }} AS physpec
        ON COALESCE(t.move_type, s.type) = physpec.type
    WHERE
        COALESCE(t.move_power, s.power) <> 'N/A'
        AND COALESCE(t.move_power, s.power) IS NOT null
),

type_effectiveness_lookup AS (
    SELECT
        attacking_type,
        defending_type AS type1,
        CAST(null AS VARCHAR) AS type2,
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

matchups AS (
    SELECT DISTINCT
        a.game_stage,
        a.trainer AS attacker,
        d.trainer AS defender,
        a.pkmn_id AS attacker_pkmn_id,
        d.pkmn_id AS defender_pkmn_id,
        a.pokemon AS attacker_pokemon,
        d.pokemon AS defender_pokemon,
        a.speed AS attacker_speed,
        d.speed AS defender_speed,
        a.pkmn_level AS attacker_level,
        d.pkmn_level AS defender_level,
        d.hp AS defender_hp,
        tel.total_effectiveness AS attacker_move_type_effectiveness,
        a.move,
        a.move_type,
        a.move_origin,
        a.move_acc,
        a.move_stab,
        a.move_power,
        a.move_hits_min,
        a.is_single_use_tm,
        CASE WHEN a.move_stat = 'Attack' THEN d.defence ELSE d.special END AS defender_stat,
        CASE WHEN a.move_stat = 'Attack' THEN a.attack ELSE a.special END AS attacker_stat
    FROM all_pokemon_with_stats AS a
    INNER JOIN all_pokemon_with_stats AS d
        ON a.player <> d.player
        AND a.game_order <= d.game_order
        AND a.game_stage = d.game_stage
    INNER JOIN type_effectiveness_lookup AS tel
        ON a.move_type = tel.attacking_type
        AND d.type1 = tel.type1
        AND (d.type2 = tel.type2 OR (tel.type2 IS null AND d.type2 IS null))
    WHERE a.move_acc <> 'N/A'
),

-- === Battle Analysis (formerly int_battle_analysis) ===
damage_dealt AS (
    -- Player attacking trainer perspective
    SELECT
        game_stage,
        'Player' as attacker,
        defender as defender,
        attacker_pkmn_id,
        defender_pkmn_id,
        attacker_pokemon,
        defender_pokemon,
        attacker_level,
        defender_level,
        attacker_speed,
        defender_speed,
        move,
        move_origin,
        is_single_use_tm,
        CASE WHEN move_power = 'KO' THEN TRUE ELSE FALSE END as is_ohko_move,
        TRY_CAST(move_acc AS DOUBLE) as move_accuracy,
        {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }} as damage_min,
        CASE
            WHEN {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }} = 0 THEN NULL
            ELSE defender_hp / {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }}
        END as attempts_to_ko,
        ROW_NUMBER() OVER(PARTITION BY attacker_pkmn_id, defender_pkmn_id ORDER BY attempts_to_ko ASC) as rn
    FROM matchups
    WHERE attacker = 'Player'
    QUALIFY ROW_NUMBER() OVER(PARTITION BY attacker_pkmn_id, defender_pkmn_id ORDER BY attempts_to_ko ASC) <= 4

    UNION ALL

    -- Trainer attacking player perspective
    SELECT
        game_stage,
        attacker as attacker,
        'Player' as defender,
        attacker_pkmn_id,
        defender_pkmn_id,
        attacker_pokemon,
        defender_pokemon,
        attacker_level,
        defender_level,
        attacker_speed,
        defender_speed,
        move,
        move_origin,
        is_single_use_tm,
        CASE WHEN move_power = 'KO' THEN TRUE ELSE FALSE END as is_ohko_move,
        TRY_CAST(move_acc AS DOUBLE) as move_accuracy,
        {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }} as damage_min,
        CASE
            WHEN {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }} = 0 THEN NULL
            ELSE defender_hp / {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }}
        END as attempts_to_ko,
        ROW_NUMBER() OVER(PARTITION BY attacker_pkmn_id, defender_pkmn_id ORDER BY attempts_to_ko ASC) as rn
    FROM matchups
    WHERE attacker <> 'Player'
    QUALIFY ROW_NUMBER() OVER(PARTITION BY attacker_pkmn_id, defender_pkmn_id ORDER BY attempts_to_ko ASC) <= 4
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['P.attacker_pkmn_id','P.defender_pkmn_id','P.move','T.move','P.move_origin']) }} as matchup_id,
    P.game_stage,
    P.attacker as player,
    P.defender as trainer,
    CASE WHEN GL.trainer IS NOT NULL THEN 1 ELSE 0 END as is_gym_leader,
    P.attacker_pkmn_id as player_pkmn_id,
    P.attacker_pokemon as player_pokemon,
    P.attacker_level as player_pkmn_level,
    P.move as player_pkmn_move,
    P.move_origin as player_pkmn_move_origin,
    P.is_single_use_tm as player_move_single_use_tm,
    P.defender_pkmn_id as trainer_pkmn_id,
    P.defender_pokemon as trainer_pokemon,
    P.defender_level as trainer_pkmn_level,
    T.move as trainer_pkmn_move,
    P.defender_speed as trainer_speed,
    P.attacker_speed as player_speed,
    P.attempts_to_ko as player_attempts_to_ko,
    T.attempts_to_ko as trainer_attempts_to_ko,
    {{ calculate_battle_outcome() }} AS battle_score
FROM damage_dealt P
INNER JOIN damage_dealt T
    ON T.attacker_pkmn_id = P.defender_pkmn_id AND P.attacker_pkmn_id = T.defender_pkmn_id
LEFT JOIN (SELECT DISTINCT trainer FROM {{ ref('stg_trainers_gym_leaders') }}) GL
    ON P.defender = GL.trainer
WHERE P.attacker = 'Player'
    AND T.rn = 1
