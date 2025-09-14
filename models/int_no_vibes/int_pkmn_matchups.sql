 WITH player_team_options as (
    SELECT
        1 as player,
        'Player' as trainer,
        NULL as type,
        game_stage,
        game_order,
        T.pokemon,
        level_cap as pkmn_level,
        {{ calculate_hp_rby('P.hp','T.level_cap','7') }} as pkmn_hp,
        {{ calculate_stat_rby('P.attack','T.level_cap','7') }} as pkmn_attack,
        {{ calculate_stat_rby('P.defence','T.level_cap','7') }} as pkmn_defence,
        {{ calculate_stat_rby('P.special','T.level_cap','7') }} as pkmn_special,
        {{ calculate_stat_rby('P.speed','T.level_cap','7') }} as pkmn_speed,
        type1,
        type2,
        move,
        move_origin,
        move_type,
        CASE
            WHEN move_type = type1 THEN 1.5
            WHEN move_type = type2 THEN 1.5
            ELSE 1
        END AS move_stab,
        move_power,
        move_accuracy,
        move_pp,
        move_hits,
        move_hits_min,
        move_hits_max,
        critical_hit_ratio,
        move_stat_used
    FROM {{ ref('int_player_teams_movesets') }} AS T
    INNER JOIN {{ ref('stg_pkmn_stats') }} AS P on P.pokemon = T.pokemon
),

trainer_team as (
    SELECT
        0 as player,
        trainer,
        type,
        game_stage,
        game_order,
        P.pokemon,
        pkmn_level,
        {{ calculate_hp_rby('P.hp','T.pkmn_level','7') }} as pkmn_hp,
        {{ calculate_stat_rby('P.attack','T.pkmn_level','7') }} as pkmn_attack,
        {{ calculate_stat_rby('P.defence','T.pkmn_level','7') }} as pkmn_defence,
        {{ calculate_stat_rby('P.special','T.pkmn_level','7') }} as pkmn_special,
        {{ calculate_stat_rby('P.speed','T.pkmn_level','7') }} as pkmn_speed,
        type1,
        type2,
        move,
        NULL as move_origin,
        move_type,
        CASE
            WHEN move_type = type1 THEN 1.5
            WHEN move_type = type2 THEN 1.5
            ELSE 1
        END AS move_stab,
        move_power,
        move_accuracy,
        move_pp,
        move_hits,
        move_hits_min,
        move_hits_max,
        critical_hit_ratio,
        move_stat_used
    FROM {{ ref('int_trainer_teams_movesets') }} AS T
    INNER JOIN {{ ref('stg_pkmn_stats') }} AS P on P.pokemon = T.pokemon
),

player_and_trainer_teams as (
    SELECT * FROM player_team_options
    UNION ALL 
    SELECT * FROM trainer_team
),

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
),

attackers_verses_defenders as (

    SELECT 
        A.player as attacker_is_player,
        A.trainer as attacker_trainer,
        A.type as attacker_trainer_type,
        A.game_stage as attacker_game_stage,
        A.game_order as attacker_game_order,
        A.pokemon as attacker_pokemon,
        A.pkmn_level as attacker_pkmn_level,
        A.pkmn_hp as attacker_pkmn_hp,
        A.pkmn_attack as attacker_pkmn_attack,
        A.pkmn_defence as attacker_pkmn_defence,
        A.pkmn_special as attacker_pkmn_special,
        A.pkmn_speed as attacker_pkmn_speed,
        A.type1 as attacker_type1,
        A.type2 as attacker_type2,
        A.move as attacker_move,
        A.move_origin as attacker_move_origin,
        A.move_type as attacker_move_type,
        A.move_stab as attacker_move_stab,
        A.move_power as attacker_move_power,
        A.move_accuracy as attacker_move_accuracy,
        A.move_pp as attacker_move_pp,
        A.move_hits as attacker_move_hits,
        A.move_hits_min as attacker_move_hits_min,
        A.move_hits_max as attacker_move_hits_max,
        A.critical_hit_ratio as attacker_critical_hit_ratio,
        A.move_stat_used as attacker_move_stat_used,
        tel.total_effectiveness AS attacker_move_type_effectiveness,
        D.trainer as defender_trainer,
        D.type as defender_trainer_type,
        D.game_stage as defender_game_stage,
        D.game_order as defender_game_order,
        D.pokemon as defender_pokemon,
        D.pkmn_level as defender_pkmn_level,
        D.pkmn_hp as defender_pkmn_hp,
        D.pkmn_attack as defender_pkmn_attack,
        D.pkmn_defence as defender_pkmn_defence,
        D.pkmn_special as defender_pkmn_special,
        D.pkmn_speed as defender_pkmn_speed,
        D.type1 as defender_type1,
        D.type2 as defender_type2,
        D.move as defender_move,
        D.move_origin as defender_move_origin,
        D.move_type as defender_move_type,
        D.move_stab as defender_move_stab,
        D.move_power as defender_move_power,
        D.move_accuracy as defender_move_accuracy,
        D.move_pp as defender_move_pp,
        D.move_hits as defender_move_hits,
        D.move_hits_min as defender_move_hits_min,
        D.move_hits_max as defender_move_hits_max,
        D.critical_hit_ratio as defender_critical_hit_ratio,
        D.move_stat_used as defender_move_stat_used,
        CASE WHEN a.move_stat_used = 'Attack' THEN D.pkmn_defence ELSE D.pkmn_special END
        AS defender_stat,
    CASE WHEN a.move_stat_used = 'Attack' THEN A.pkmn_attack ELSE A.pkmn_special END
        AS attacker_stat
FROM player_and_trainer_teams as A
    INNER JOIN player_and_trainer_teams as D 
        ON A.player <> D.player
        AND A.game_order = D.game_order
    INNER JOIN type_effectiveness_lookup AS tel
        ON A.move_type = tel.attacking_type
        AND D.type1 = tel.type1
        AND (D.type2 = tel.type2 OR (tel.type2 IS null AND D.type2 IS null))
    WHERE A.move_accuracy <> 'N/A'
    AND A.game_stage = 'Badge_2'

)



SELECT 
attacker_is_player,
attacker_trainer,
attacker_trainer_type,
attacker_game_stage,
attacker_game_order,
attacker_pokemon,
attacker_pkmn_level,
attacker_move,
attacker_move_origin,

defender_trainer,
defender_trainer_type,
defender_pokemon,
defender_pkmn_level,
CASE WHEN attacker_move_power = 'KO' THEN TRUE ELSE FALSE END as is_ohko_move,
TRY_CAST(attacker_move_accuracy AS DOUBLE) as move_accuracy,
{{ calculate_damage_rby('defender_stat','defender_pkmn_hp','attacker_stat','attacker_pkmn_level','attacker_move','attacker_move_accuracy','attacker_move_type_effectiveness','attacker_move_stab','attacker_move_power','attacker_move_hits_min') }} as damage_min,
CASE 
    WHEN {{ calculate_damage_rby('defender_stat','defender_pkmn_hp','attacker_stat','attacker_pkmn_level','attacker_move','attacker_move_accuracy','attacker_move_type_effectiveness','attacker_move_stab','attacker_move_power','attacker_move_hits_min') }} = 0 THEN NULL
    ELSE defender_pkmn_hp / {{ calculate_damage_rby('defender_stat','defender_pkmn_hp','attacker_stat','attacker_pkmn_level','attacker_move','attacker_move_accuracy','attacker_move_type_effectiveness','attacker_move_stab','attacker_move_power','attacker_move_hits_min') }} 
END as attempts_to_ko,
ROW_NUMBER() OVER(PARTITION BY attacker_trainer, attacker_pokemon, attacker_pkmn_level, defender_trainer, defender_pokemon, defender_pkmn_level ORDER BY attempts_to_ko ASC) as rn

FROM attackers_verses_defenders
