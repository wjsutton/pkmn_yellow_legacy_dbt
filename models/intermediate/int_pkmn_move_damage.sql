WITH matchups as (

    SELECT DISTINCT
        A.next_gym as game_stage,
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
    FROM {{ ref('int_pkmn_move_damage_prep') }} as A
    INNER JOIN {{ ref('int_pkmn_move_damage_prep') }} as D on A.player <> D.player AND A.order <= D.order AND A.next_gym = D.next_gym
    INNER JOIN {{ ref('stg_moves_type_effectiveness') }} as TE1 on TE1.attacking_type = A.move_type AND TE1.defending_type = D.type1
    LEFT JOIN {{ ref('stg_moves_type_effectiveness') }} as TE2 on TE2.attacking_type = A.move_type AND TE2.defending_type = D.type2

)

, damage_dealt as (

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
        {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }}  as damage_min,
        defender_hp / {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }} as attempts_to_ko,
        ROW_NUMBER() OVER(PARTITION BY attacker_pkmn_id, defender_pkmn_id ORDER BY attempts_to_ko ASC) as rn
    FROM matchups
    QUALIFY ROW_NUMBER() OVER(PARTITION BY attacker_pkmn_id, defender_pkmn_id ORDER BY attempts_to_ko ASC) <= 4

)

SELECT 
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
    -- CASE WHEN P.attacker_speed > P.defender_speed THEN 1 ELSE 0 END as speed_diff_metric,
    -- 1/(CASE WHEN P.hits_to_ko_min < 1 THEN 1 ELSE P.hits_to_ko_min END) as player_hits_to_ko_metric,
    -- -1/(CASE WHEN T.hits_to_ko_min < 1 THEN 1 ELSE T.hits_to_ko_min END) as trainer_hits_to_ko_metric,
    -- speed_diff_metric +P.attacker_speed player_hits_to_ko_metric + trainer_hits_to_ko_metric as metric_total
    CASE 
-- Special case for OHKO moves from trainer
WHEN T.is_ohko_move THEN
    -- If player goes first and can one-shot, they win
    CASE 
        WHEN P.attacker_speed > P.defender_speed AND P.attempts_to_ko <= 1 THEN 1.0
        -- If player goes first but needs multiple hits
        WHEN P.attacker_speed > P.defender_speed THEN
            -- Probability of surviving OHKO move long enough to win
            (1 - T.move_accuracy) * (CASE WHEN P.attempts_to_ko <= 2 THEN 1.0 
                                        ELSE 1.0 - ((P.attempts_to_ko - 2) / 5) END)
        ELSE 
            -- Player goes second, only chance is surviving OHKO move
            (1 - T.move_accuracy) * 0.5
    END

-- Player goes first and KOs trainer before trainer can attack
WHEN P.attacker_speed > P.defender_speed AND P.attempts_to_ko = 1 THEN 1.0

-- Player goes first but needs multiple hits
WHEN P.attacker_speed > P.defender_speed THEN
    -- If player KOs trainer before trainer KOs player
    CASE WHEN P.attempts_to_ko < T.attempts_to_ko + 1 THEN
        -- Score based on remaining health percentage after battle
        1.0 - (CEIL(P.attempts_to_ko - 1) / T.attempts_to_ko)
    ELSE 
        -- For losing matchups, calculate a small non-zero score based on the difference
        -- This will be between -0.1 and 0 (closer to 0 is better)
        GREATEST(-0.1, -0.1 * (P.attempts_to_ko - T.attempts_to_ko) / NULLIF(T.attempts_to_ko, 0))
    END

-- Trainer goes first
WHEN P.attacker_speed <= P.defender_speed THEN
    -- If player can still KO trainer before being KO'd
    CASE WHEN P.attempts_to_ko <= T.attempts_to_ko THEN
        -- Score based on remaining health percentage after battle
        1.0 - (CEIL(P.attempts_to_ko) / T.attempts_to_ko)
    ELSE 
        -- For losing matchups, calculate a small non-zero score based on the difference
        -- This will be between -0.2 and -0.1 (closer to -0.1 is better)
        -- These are slightly worse than when player goes first
        GREATEST(-0.2, -0.1 - 0.1 * (P.attempts_to_ko - T.attempts_to_ko) / NULLIF(T.attempts_to_ko, 0))
    END
END AS battle_score
FROM damage_dealt as P
INNER JOIN damage_dealt as T on T.attacker_pkmn_id = P.defender_pkmn_id AND P.attacker_pkmn_id = T.defender_pkmn_id
LEFT JOIN (SELECT DISTINCT trainer FROM {{ ref('stg_trainers_gym_leaders') }} ) as GL on P.defender = GL.trainer
WHERE P.attacker = 'Player'
AND T.rn = 1
