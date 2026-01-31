{% macro calculate_battle_outcome() %}
    CASE
    -- Special case for OHKO moves from trainer.
    -- OHKO rows only exist when trainer is faster (slower cases filtered
    -- in damage calc, since Gen 1 OHKO moves always miss slower users).
    -- Score = survival probability mapped to [-1, 1]: survive N turns of
    -- acc% OHKO chance, where N = ceil(player attempts to KO trainer).
    WHEN is_ohko_move THEN
        CASE
            WHEN player_attempts_to_ko IS NULL THEN -1.0
            ELSE POWER(1.0 - move_accuracy, CEIL(player_attempts_to_ko)) * 2.0 - 1.0
        END

    -- Player goes first and KOs trainer before trainer can attack
    WHEN player_speed > trainer_speed AND player_attempts_to_ko = 1 THEN 1.0

    -- Player goes first but needs multiple hits
    WHEN player_speed > trainer_speed THEN
        -- If player KOs trainer before trainer KOs player
        CASE WHEN player_attempts_to_ko < trainer_attempts_to_ko + 1 THEN
            -- Score based on remaining health percentage after battle
            1.0 - (CEIL(player_attempts_to_ko - 1) / trainer_attempts_to_ko)
        ELSE
            -- For losing matchups, calculate a small non-zero score based on the difference
            -- This will be between -0.1 and 0 (closer to 0 is better)
            GREATEST(-0.1, -0.1 * (player_attempts_to_ko - trainer_attempts_to_ko) / NULLIF(trainer_attempts_to_ko, 0))
        END

    -- Trainer goes first
    WHEN player_speed <= trainer_speed THEN
        -- If player can still KO trainer before being KO'd
        CASE WHEN player_attempts_to_ko <= trainer_attempts_to_ko THEN
            -- Score based on remaining health percentage after battle
            1.0 - (CEIL(player_attempts_to_ko) / trainer_attempts_to_ko)
        ELSE
            -- For losing matchups, calculate a small non-zero score based on the difference
            -- This will be between -0.2 and -0.1 (closer to -0.1 is better)
            -- These are slightly worse than when player goes first
            GREATEST(-0.2, -0.1 - 0.1 * (player_attempts_to_ko - trainer_attempts_to_ko) / NULLIF(trainer_attempts_to_ko, 0))
        END
    END
{% endmacro %}