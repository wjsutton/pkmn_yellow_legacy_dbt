WITH player_pokemon_with_moves AS (
    -- Player Pokemon with available moves using unified move sources
    SELECT 
        'Player' as trainer,
        PA.game_stage,
        PA.earliest_route as order,
        'Player_' || PA.pokemon ||'_1' as pkmn_id,
        PA.pokemon,
        PA.level_cap as level,
        MS.move,
        MS.move_origin,
        MS.move_type,
        MS.move_power,
        MS.move_accuracy,
        MS.move_stat_used,
        MS.is_single_use_tm
    FROM {{ ref('int_pokemon_availability') }} PA 
    INNER JOIN {{ ref('stg_move_sources_unified') }} MS ON PA.pokemon = MS.pokemon
    WHERE ((MS.level <= PA.level_cap AND MS.is_level_up_move = 1)
        OR (MS.route_order <= PA.earliest_route AND MS.is_level_up_move = 0))
        AND MS.is_damaging_move = 1  -- Only damaging moves for battle analysis
    GROUP BY ALL
),

trainer_pokemon_with_moves AS (
    -- Trainer Pokemon from roster (unchanged)
    SELECT 
        trainer,
        game_stage,
        "order",
        pkmn_id,
        pokemon,
        "level",
        'trainer' as move_origin,
        move,
        NULL as move_type,  -- Will join with move stats
        NULL as move_power,
        NULL as move_accuracy,
        NULL as move_stat_used,
        0 as is_single_use_tm
    FROM {{ ref('int_trainer_roster') }} t
    UNPIVOT(move FOR move_slot IN (move_1, move_2, move_3, move_4)) AS unpvt
    WHERE move IS NOT NULL
),

-- Combine all pokemon with their stats (using pre-calculated stats)
all_pokemon_with_stats AS (
    SELECT 
        CASE WHEN T.trainer = 'Player' THEN 1 ELSE 0 END as player,
        T.trainer,
        T.game_stage,
        T.order,
        T.pkmn_id,
        T.pokemon,
        T.level,
        PS.type1,
        PS.type2,
        T.move,
        T.move_origin,
        COALESCE(T.move_type, S.type) as move_type,
        CASE 
            WHEN COALESCE(T.move_type, S.type) = PS.type1 THEN 1.5
            WHEN COALESCE(T.move_type, S.type) = PS.type2 THEN 1.5
            ELSE 1
        END as move_stab,
        COALESCE(T.move_stat_used, PhySpec.stat_used) as move_stat,
        COALESCE(T.move_power, S.power) as move_power,
        COALESCE(T.move_accuracy, S.acc) as move_acc,
        S.hits_min as move_hits_min,
        S.critical_hit_ratio,
        T.is_single_use_tm,
        -- Use pre-calculated stats instead of calculating on-the-fly
        PSC.calculated_hp as hp,
        PSC.calculated_attack as attack,
        PSC.calculated_defense as defense,
        PSC.calculated_special as special,
        PSC.calculated_speed as speed
    FROM (
        SELECT * FROM player_pokemon_with_moves
        UNION ALL
        SELECT * FROM trainer_pokemon_with_moves
    ) T
    INNER JOIN {{ ref('stg_pkmn_stats') }} PS ON T.pokemon = PS.pokemon
    INNER JOIN {{ ref('stg_pkmn_stats_calculated') }} PSC 
        ON PS.pokemon = PSC.pokemon AND T.level = PSC.level
    LEFT JOIN {{ ref('stg_moves_stats') }} S ON T.move = S.move
    LEFT JOIN {{ ref('stg_moves_phys_spec') }} PhySpec ON COALESCE(T.move_type, S.type) = PhySpec.type
    WHERE COALESCE(T.move_power, S.power) <> 'N/A'
        AND COALESCE(T.move_power, S.power) IS NOT NULL
),

-- Create type effectiveness lookup for all relevant combinations
type_effectiveness_lookup AS (
    SELECT 
        TE1.attacking_type,
        TE1.defending_type as type1,
        TE2.defending_type as type2,
        TE1.damage_modifier * COALESCE(TE2.damage_modifier, 1) as total_effectiveness
    FROM {{ ref('stg_moves_type_effectiveness') }} TE1
    LEFT JOIN {{ ref('stg_moves_type_effectiveness') }} TE2 
        ON TE1.attacking_type = TE2.attacking_type
    WHERE TE2.defending_type IS NULL OR TE2.defending_type != TE1.defending_type
),

-- Optimized matchups with pre-calculated effectiveness
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
        TEL.total_effectiveness as attacker_move_type_effectiveness,
        CASE WHEN A.move_stat='Attack' THEN D.defense ELSE D.special END as defender_stat,
        CASE WHEN A.move_stat='Attack' THEN A.attack ELSE A.special END as attacker_stat,
        A.move,
        A.move_type,
        A.move_origin,
        A.move_acc,
        A.move_stab,
        A.move_power,
        A.move_hits_min,
        A.is_single_use_tm
    FROM all_pokemon_with_stats A
    INNER JOIN all_pokemon_with_stats D 
        ON A.player <> D.player AND A.order <= D.order AND A.game_stage = D.game_stage
    INNER JOIN type_effectiveness_lookup TEL
        ON TEL.attacking_type = A.move_type 
        AND TEL.type1 = D.type1 
        AND (TEL.type2 = D.type2 OR (TEL.type2 IS NULL AND D.type2 IS NULL))
),

-- Damage calculations (using existing macro but with optimized inputs)
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
        is_single_use_tm,
        CASE WHEN move_power = 'KO' THEN TRUE ELSE FALSE END as is_ohko_move,
        move_acc::double as move_accuracy,
        {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }} as damage_min,
        defender_hp / {{ calculate_damage_rby('defender_stat','defender_hp','attacker_stat','attacker_level','move','move_acc','attacker_move_type_effectiveness','move_stab','move_power','move_hits_min') }} as attempts_to_ko,
        ROW_NUMBER() OVER(PARTITION BY attacker_pkmn_id, defender_pkmn_id ORDER BY attempts_to_ko ASC) as rn
    FROM matchups
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