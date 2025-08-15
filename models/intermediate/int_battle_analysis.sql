WITH matchups AS (
    SELECT *
    FROM {{ ref('int_battle_matchups') }}
    WHERE move_acc <> 'N/A'
),

-- Damage calculations creating explicit bidirectional battle pairs
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
    
    -- Trainer attacking player perspective (same battles, reversed roles)
    SELECT 
        game_stage,
        attacker as attacker,  -- This will be the trainer name
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
    WHERE attacker <> 'Player'  -- This captures trainer attacking player scenarios
    QUALIFY ROW_NUMBER() OVER(PARTITION BY attacker_pkmn_id, defender_pkmn_id ORDER BY attempts_to_ko ASC) <= 4
)

-- Final output with same structure as original
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