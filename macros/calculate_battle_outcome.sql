{% macro calculate_battle_outcome() %}
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
    END
{% endmacro %}