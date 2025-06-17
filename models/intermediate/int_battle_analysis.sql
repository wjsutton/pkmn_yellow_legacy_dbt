WITH possible_moves AS (
    {{ get_move_sources() }}
),

all_pkmn AS (
    -- Player Pokemon
    SELECT 
        'Player' as trainer,
        T.game_stage,
        T.earliest_route as order,
        'Player_' || T.pokemon ||'_1' as pkmn_id,
        T.pokemon,
        MAX(T.level_cap) as level,
        M.move_origin,
        M.move
    FROM {{ ref('int_pokemon_availability') }} as T 
    INNER JOIN possible_moves as M ON T.pokemon = M.pokemon
    WHERE ((M.level <= T.level_cap AND M.order IS NULL)
    OR (M.order <= T.earliest_route AND M.level IS NULL))
    AND M.move NOT IN ('Horn Drill','Fissure','Guillotine','Explosion','Selfdestruct')
    GROUP BY ALL

    UNION 

    -- Trainer Pokemon
    SELECT 
        trainer,
        game_stage,
        "order",
        pkmn_id,
        pokemon,
        "level",
        'trainer' as move_origin,
        move
    FROM {{ ref('int_trainer_roster') }} as t
    UNPIVOT(move FOR move_slot IN (move_1, move_2, move_3, move_4)) AS unpvt
),

pokemon_with_stats AS (
    SELECT 
        CASE WHEN T.trainer = 'Player' THEN 1 ELSE 0 END as player,
        T.trainer,
        T.game_stage,
        T.order,
        T.pkmn_id,
        T.pokemon,
        T.level,
        P.type1,
        P.type2,
        T.move,
        T.move_origin,
        S.type as move_type,
        CASE 
            WHEN S.type = P.type1 THEN 1.5
            WHEN S.type = P.type2 THEN 1.5
            ELSE 1
        END as move_stab,
        PS.stat_used as move_stat,
        S.power as move_power,
        S.acc as move_acc,
        S.hits_min as move_hits_min,
        S.critical_hit_ratio as critical_hit_ratio,
        {{ calculate_hp_rby('P.hp','T.level','7') }} as hp,
        {{ calculate_stat_rby('P.attack','T.level','7') }} as attack,
        {{ calculate_stat_rby('P.defense','T.level','7') }} as defense,
        {{ calculate_stat_rby('P.special','T.level','7') }} as special,
        {{ calculate_stat_rby('P.speed','T.level','7') }} as speed
    FROM all_pkmn as T
    INNER JOIN {{ ref('stg_moves_stats') }} as S ON T.move = S.move
    INNER JOIN {{ ref('stg_pkmn_stats') }} as P ON P.pokemon = T.pokemon
    INNER JOIN {{ ref('stg_moves_phys_spec') }} as PS ON PS.type = S.type
    WHERE S.power <> 'N/A'
),

matchups AS (
    SELECT DISTINCT
        A.game_stage,
        A.trainer as attacker,
        D.trainer as defender,
        A.pkmn_id as attacker_pkmn_id,
        D.pkmn_id as defender_pkmn_id,
        A.pokemon as attacker_pokemon,
        D.pokemon as defender_pokemon,
        A.speed as attacker_speed,
        D.speed as defender_speed,
        A.level as attacker_level,
        D.level as defender_level,
        D.hp as defender_hp,
        TE1.damage_modifier * COALESCE(TE2.damage_modifier,1) as attacker_move_type_effectiveness,
        CASE WHEN A.move_stat='Attack' THEN D.defense ELSE D.special END as defender_stat,
        CASE WHEN A.move_stat='Attack' THEN A.attack ELSE A.special END as attacker_stat,
        A.move,
        A.move_type,
        A.move_origin,
        A.move_acc,
        A.move_stab,
        A.move_power,
        A.move_hits_min
    FROM pokemon_with_stats as A
    INNER JOIN pokemon_with_stats as D 
        ON A.player <> D.player AND A.order <= D.order AND A.game_stage = D.game_stage
    INNER JOIN {{ ref('stg_moves_type_effectiveness') }} as TE1 
        ON TE1.attacking_type = A.move_type AND TE1.defending_type = D.type1
    LEFT JOIN {{ ref('stg_moves_type_effectiveness') }} as TE2 
        ON TE2.attacking_type = A.move_type AND TE2.defending_type = D.type2
),

damage_dealt AS (
    SELECT 
        game_stage,
        attacker,
        defender,
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
        CASE WHEN move_power = 'KO' THEN TRUE ELSE FALSE END as is_ohko_move,
        move_acc::double as move_accuracy,
        {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }} as damage_min,
        defender_hp / {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }} as attempts_to_ko,
        ROW_NUMBER() OVER(PARTITION BY attacker_pkmn_id, defender_pkmn_id ORDER BY attempts_to_ko ASC) as rn
    FROM matchups
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
    P.defender_pkmn_id as trainer_pkmn_id,
    P.defender_pokemon as trainer_pokemon,
    P.defender_level as trainer_pkmn_level,
    T.move as trainer_pkmn_move,
    P.defender_speed as trainer_speed,
    P.attacker_speed as player_speed,
    P.attempts_to_ko as player_attempts_to_ko,
    T.attempts_to_ko as trainer_attempts_to_ko,
    {{ calculate_battle_outcome() }} AS battle_score
FROM damage_dealt as P
INNER JOIN damage_dealt as T 
    ON T.attacker_pkmn_id = P.defender_pkmn_id AND P.attacker_pkmn_id = T.defender_pkmn_id
LEFT JOIN (SELECT DISTINCT trainer FROM {{ ref('stg_trainers_gym_leaders') }}) as GL 
    ON P.defender = GL.trainer
WHERE P.attacker = 'Player'
AND T.rn = 1