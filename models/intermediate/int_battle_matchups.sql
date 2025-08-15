WITH player_pokemon_with_moves AS (
    -- Player Pokemon with available moves using unified move sources
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
        ms.is_single_use_tm,
        'Player_' || pa.pokemon || '_1' AS pkmn_id
    FROM {{ ref('int_pokemon_availability') }} AS pa
    INNER JOIN
        {{ ref('stg_move_sources_unified') }} AS ms
        ON pa.pokemon = ms.pokemon
    WHERE (
        (ms.pkmn_level <= pa.level_cap AND ms.is_level_up_move = 1)
        OR (ms.route_order <= pa.earliest_route AND ms.is_level_up_move = 0)
    )
    AND ms.is_damaging_move = 1  -- Only damaging moves for battle analysis
),

trainer_pokemon_with_moves AS (
    -- Trainer Pokemon from roster with only damaging moves
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
        pkmn_id,
    FROM {{ ref('int_trainer_roster') }}
    UNPIVOT (move FOR move_slot IN (move_1, move_2, move_3, move_4)) AS unpvt
    INNER JOIN {{ ref('stg_moves_stats') }} AS ms ON unpvt.move = ms.move
    LEFT JOIN {{ ref('stg_moves_phys_spec') }} AS physpec ON ms.type = physpec.type
    WHERE
        unpvt.move IS NOT null
        AND ms.power <> 'N/A'  -- Only damaging moves for battle analysis
        AND ms.power IS NOT null
        -- Exclude non-numeric power values
        AND ms.power NOT IN ('Copy', 'Set', 'Var Dmg')
),

player_and_trainer_pokemon_moves AS (
    SELECT * FROM player_pokemon_with_moves
        UNION ALL
    SELECT * FROM trainer_pokemon_with_moves
),

-- Combine all pokemon with their stats (using pre-calculated stats)
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
        psc.calculated_defense AS defense,
        psc.calculated_special AS special,
        psc.calculated_speed AS speed,
        CASE WHEN t.trainer = 'Player' THEN 1 ELSE 0 END AS player,
        -- Use pre-calculated stats instead of calculating on-the-fly
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
    INNER JOIN {{ ref('stg_pkmn_stats_calculated') }} AS psc
        ON ps.pokemon = psc.pokemon AND t.pkmn_level = psc.pkmn_level
    LEFT JOIN {{ ref('stg_moves_stats') }} AS s ON t.move = s.move
    LEFT JOIN
        {{ ref('stg_moves_phys_spec') }} AS physpec
        ON COALESCE(t.move_type, s.type) = physpec.type
    WHERE
        COALESCE(t.move_power, s.power) <> 'N/A'
        AND COALESCE(t.move_power, s.power) IS NOT null
),

-- Create type effectiveness lookup for all relevant combinations
type_effectiveness_lookup AS (
    -- Single-type effectiveness (type2 = NULL)
    SELECT
        attacking_type,
        defending_type AS type1,
        CAST(null AS VARCHAR) AS type2,
        damage_modifier AS total_effectiveness
    FROM {{ ref('stg_moves_type_effectiveness') }}

    UNION ALL

    -- Dual-type effectiveness (both types)
    SELECT
        te1.attacking_type,
        te1.defending_type AS type1,
        te2.defending_type AS type2,
        te1.damage_modifier * te2.damage_modifier AS total_effectiveness
    FROM {{ ref('stg_moves_type_effectiveness') }} AS te1
    INNER JOIN {{ ref('stg_moves_type_effectiveness') }} AS te2
        ON
            te1.attacking_type = te2.attacking_type
            AND te1.defending_type <> te2.defending_type
)


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
    CASE WHEN a.move_stat = 'Attack' THEN d.defense ELSE d.special END
        AS defender_stat,
    CASE WHEN a.move_stat = 'Attack' THEN a.attack ELSE a.special END
        AS attacker_stat
FROM all_pokemon_with_stats AS a
INNER JOIN all_pokemon_with_stats AS d
    ON
        a.player <> d.player
        AND a.game_order <= d.game_order
        AND a.game_stage = d.game_stage
INNER JOIN type_effectiveness_lookup AS tel
    ON
        a.move_type = tel.attacking_type
        AND d.type1 = tel.type1
        AND (d.type2 = tel.type2 OR (tel.type2 IS null AND d.type2 IS null))
