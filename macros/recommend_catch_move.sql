{% macro recommend_catch_move(
    player_pokemon, player_level,
    enemy_pokemon, enemy_level, enemy_current_hp, enemy_max_hp,
    move1, move2, move3, move4,
    pp1, pp2, pp3, pp4,
    want_status
) %}

{#
    recommend_catch_move (catalog key: catch_move) — best move for catching a wild
    Pokemon. The defensive sibling of recommend_battle_move (best_move): that macro
    maximises a KO, this one avoids it (you want the target alive to catch).

    When want_status = 'true':
      Returns the best status move (SLEEP > PARALYSIS) with PP remaining.
      Uses stg_moves_stats.effect text to detect sleep/paralysis moves.

    When want_status = 'false':
      Returns the best weakening move — highest damage that won't KO.
      Uses calculate_damage_rby with type effectiveness and STAB.
      If ALL moves would KO, returns the lowest-damage move with safe=false.

    Returns columns: move_name, move_slot, expected_damage, is_status, status_type, safe
#}

WITH player_moves AS (
    SELECT 1 AS slot, '{{ move1 }}' AS move_name, {{ pp1 }} AS pp
    UNION ALL
    SELECT 2, '{{ move2 }}', {{ pp2 }}
    UNION ALL
    SELECT 3, '{{ move3 }}', {{ pp3 }}
    UNION ALL
    SELECT 4, '{{ move4 }}', {{ pp4 }}
),

move_data AS (
    SELECT
        pm.slot,
        pm.move_name,
        pm.pp,
        ms.effect,
        ms.type AS move_type,
        ms.power,
        ms.acc,
        ms.hits,
        ps.stat_used,
        -- Detect status from effect text
        -- effect text uses a non-breaking space (chr 160) between words, e.g.
        -- 'Puts the target to\xa0sleep.' — normalise it so the LIKE patterns match.
        CASE
            WHEN REPLACE(LOWER(ms.effect), chr(160), ' ') LIKE '%puts the target to sleep%' THEN 'SLEEP'
            WHEN REPLACE(LOWER(ms.effect), chr(160), ' ') LIKE '%paralyzes the target%' THEN 'PARALYSIS'
            ELSE NULL
        END AS status_type,
        -- Is this a pure status move (no damage)?
        CASE WHEN ms.power = 'N/A' THEN true ELSE false END AS is_status_move
    FROM player_moves pm
    LEFT JOIN {{ ref('stg_moves_stats') }} ms ON pm.move_name = ms.move
    LEFT JOIN {{ ref('stg_moves_phys_spec') }} ps ON ms.type = ps.type
    WHERE pm.move_name IS NOT NULL
      AND pm.move_name != ''
      AND pm.pp > 0
),

enemy_stats AS (
    SELECT
        pokemon,
        type1,
        type2,
        hp AS base_hp,
        attack AS base_attack,
        defence AS base_defence,
        special AS base_special,
        speed AS base_speed
    FROM {{ ref('stg_pkmn_stats') }}
    WHERE UPPER(pokemon) = UPPER('{{ enemy_pokemon }}')
    LIMIT 1
),

player_stats AS (
    SELECT
        pokemon,
        type1,
        type2,
        attack AS base_attack,
        defence AS base_defence,
        special AS base_special,
        speed AS base_speed
    FROM {{ ref('stg_pkmn_stats') }}
    WHERE UPPER(pokemon) = UPPER('{{ player_pokemon }}')
    LIMIT 1
),

-- Type effectiveness for each move against the enemy
type_eff AS (
    SELECT
        md.slot,
        md.move_name,
        md.move_type,
        -- Multiply effectiveness against both enemy types
        COALESCE(te1.damage_modifier, 1.0) * COALESCE(te2.damage_modifier, 1.0) AS effectiveness
    FROM move_data md
    CROSS JOIN enemy_stats es
    LEFT JOIN {{ ref('stg_moves_type_effectiveness') }} te1
        ON md.move_type = te1.attacking_type AND es.type1 = te1.defending_type
    LEFT JOIN {{ ref('stg_moves_type_effectiveness') }} te2
        ON md.move_type = te2.attacking_type AND es.type2 = te2.defending_type
        AND es.type2 IS NOT NULL
),

damage_calc AS (
    SELECT
        md.slot,
        md.move_name,
        md.pp,
        md.is_status_move,
        md.status_type,
        md.power,
        md.acc,
        md.hits,
        te.effectiveness,
        -- STAB: 1.5 if move type matches player type
        CASE
            WHEN md.move_type = ps.type1 OR md.move_type = ps.type2 THEN 1.5
            ELSE 1.0
        END AS stab,
        -- Pick correct offensive stat (Attack for physical, Special for special)
        CASE
            WHEN md.stat_used = 'Attack'
            THEN {{ calculate_stat_rby('ps.base_attack', player_level) }}
            ELSE {{ calculate_stat_rby('ps.base_special', player_level) }}
        END AS attacker_stat,
        -- Pick correct defensive stat
        CASE
            WHEN md.stat_used = 'Attack'
            THEN {{ calculate_stat_rby('es.base_defence', enemy_level) }}
            ELSE {{ calculate_stat_rby('es.base_special', enemy_level) }}
        END AS defender_stat
    FROM move_data md
    CROSS JOIN enemy_stats es
    CROSS JOIN player_stats ps
    LEFT JOIN type_eff te ON md.slot = te.slot
),

results AS (
    SELECT
        slot AS move_slot,
        move_name,
        is_status_move,
        status_type,
        CASE
            WHEN is_status_move THEN 0
            ELSE {{ calculate_damage_rby(
                'defender_stat', enemy_current_hp,
                'attacker_stat', player_level,
                'move_name', 'acc',
                'effectiveness', 'stab',
                'power', 'hits'
            ) }}
        END AS expected_damage,
        CASE
            WHEN is_status_move THEN true
            WHEN {{ calculate_damage_rby(
                'defender_stat', enemy_current_hp,
                'attacker_stat', player_level,
                'move_name', 'acc',
                'effectiveness', 'stab',
                'power', 'hits'
            ) }} < {{ enemy_current_hp }} THEN true
            ELSE false
        END AS safe
    FROM damage_calc
)

{% if want_status == 'true' %}
-- Status mode: return best sleep/paralysis move
SELECT
    move_name,
    move_slot,
    0 AS expected_damage,
    true AS is_status,
    status_type,
    true AS safe
FROM results
WHERE status_type IS NOT NULL
  AND is_status_move = true
ORDER BY
    CASE status_type WHEN 'SLEEP' THEN 1 WHEN 'PARALYSIS' THEN 2 ELSE 3 END
LIMIT 1

{% else %}
-- Weaken mode: return highest safe damage move, or lowest damage if all would KO
SELECT
    move_name,
    move_slot,
    expected_damage,
    false AS is_status,
    NULL AS status_type,
    safe
FROM results
WHERE is_status_move = false
  AND expected_damage > 0
ORDER BY
    safe DESC,                    -- safe moves first
    CASE WHEN safe THEN expected_damage ELSE -expected_damage END DESC  -- highest safe or lowest unsafe
LIMIT 1

{% endif %}

{% endmacro %}
