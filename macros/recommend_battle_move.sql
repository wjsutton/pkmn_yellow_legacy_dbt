{% macro recommend_battle_move(
    player_pokemon, player_level,
    move1, move2, move3, move4,
    opponent_pokemon, opponent_level,
    opponent_current_hp=none,
    pp1=1, pp2=1, pp3=1, pp4=1
) %}

{#
    recommend_battle_move (catalog key: best_move) — best OFFENSIVE move to use
    in a live battle. The offensive sibling of recommend_catch_move: that macro
    avoids a KO (you want to catch); this one maximises it.

    Answers the LIVE question the marts can't precompute: given an arbitrary
    current moveset, level, and remaining HP, which of MY moves should I use?

    Same Gen-1 damage engine as the rest of the project (calculate_stat_rby,
    calculate_hp_rby, calculate_damage_rby). Fixed-damage (Seismic Toss, Night
    Shade, Dragon Rage, Sonicboom) and OHKO moves (Horn Drill / Fissure /
    Guillotine, power='KO') are handled by calculate_damage_rby itself, so they
    are modelled here rather than filtered out like mart_battle_outcomes does.

    expected_damage is accuracy-weighted (the engine bakes accuracy in), so
    will_ko / hits_to_ko are expected values — a 30%-accuracy OHKO will not be
    flagged will_ko. player_moves_first is informational (raw speed, no
    paralysis/priority modelling).

    Args:
        player_pokemon       e.g. 'Nidoking'
        player_level         current level
        move1..move4         known moves (pass '' for empty slots)
        opponent_pokemon     e.g. 'Onix'
        opponent_level       opponent level
        opponent_current_hp  optional; defaults to opponent's max HP at level
        pp1..pp4             optional PP remaining; a 0-PP move is excluded

    Returns columns: move_name, move_type, move_category, effectiveness,
                     is_stab, expected_damage, will_ko, hits_to_ko, accuracy,
                     player_moves_first, recommended
#}

{% set opp_hp_expr = opponent_current_hp if opponent_current_hp is not none
       else calculate_hp_rby('es.base_hp', opponent_level) %}

WITH player_moves AS (
    SELECT 1 AS slot, '{{ move1 }}' AS move_name, {{ pp1 }} AS pp
    UNION ALL SELECT 2, '{{ move2 }}', {{ pp2 }}
    UNION ALL SELECT 3, '{{ move3 }}', {{ pp3 }}
    UNION ALL SELECT 4, '{{ move4 }}', {{ pp4 }}
),

move_data AS (
    SELECT
        pm.slot,
        pm.move_name,
        pm.pp,
        ms.type AS move_type,
        ms.power,
        ms.acc,
        ms.hits,
        ps.stat_used,
        -- Non-damaging / un-castable power: skip the damage engine (treat as 0).
        -- calculate_damage_rby handles 'KO', 'Set', 'Var Dmg' and the named
        -- fixed-damage moves, but 'N/A' and 'Copy' would fail the ::double cast.
        CASE WHEN ms.power IS NULL OR ms.power IN ('N/A', 'Copy')
             THEN true ELSE false END AS is_status_move
    FROM player_moves pm
    LEFT JOIN {{ ref('stg_moves_stats') }} ms ON pm.move_name = ms.move
    LEFT JOIN {{ ref('stg_moves_phys_spec') }} ps ON ms.type = ps.type
    WHERE pm.move_name IS NOT NULL
      AND pm.move_name != ''
      AND pm.pp > 0
),

opponent_stats AS (
    SELECT
        pokemon, type1, type2,
        hp AS base_hp, attack AS base_attack,
        defence AS base_defence, special AS base_special, speed AS base_speed
    FROM {{ ref('stg_pkmn_stats') }}
    WHERE UPPER(pokemon) = UPPER('{{ opponent_pokemon }}')
    LIMIT 1
),

player_stats AS (
    SELECT
        pokemon, type1, type2,
        attack AS base_attack, defence AS base_defence,
        special AS base_special, speed AS base_speed
    FROM {{ ref('stg_pkmn_stats') }}
    WHERE UPPER(pokemon) = UPPER('{{ player_pokemon }}')
    LIMIT 1
),

type_eff AS (
    SELECT
        md.slot,
        COALESCE(te1.damage_modifier, 1.0) * COALESCE(te2.damage_modifier, 1.0) AS effectiveness
    FROM move_data md
    CROSS JOIN opponent_stats es
    LEFT JOIN {{ ref('stg_moves_type_effectiveness') }} te1
        ON md.move_type = te1.attacking_type AND es.type1 = te1.defending_type
    LEFT JOIN {{ ref('stg_moves_type_effectiveness') }} te2
        ON md.move_type = te2.attacking_type AND es.type2 = te2.defending_type
        AND es.type2 IS NOT NULL
),

calc AS (
    SELECT
        md.slot,
        md.move_name,
        md.move_type,
        md.power,
        md.acc,
        md.hits,
        md.is_status_move,
        md.stat_used,
        te.effectiveness,
        CASE WHEN md.move_type = ps.type1 OR md.move_type = ps.type2 THEN 1.5 ELSE 1.0 END AS stab,
        CASE WHEN md.move_type = ps.type1 OR md.move_type = ps.type2 THEN true ELSE false END AS is_stab,
        CASE WHEN md.stat_used = 'Attack'
             THEN {{ calculate_stat_rby('ps.base_attack', player_level) }}
             ELSE {{ calculate_stat_rby('ps.base_special', player_level) }} END AS attacker_stat,
        CASE WHEN md.stat_used = 'Attack'
             THEN {{ calculate_stat_rby('es.base_defence', opponent_level) }}
             ELSE {{ calculate_stat_rby('es.base_special', opponent_level) }} END AS defender_stat,
        {{ opp_hp_expr }} AS opp_hp,
        {{ calculate_stat_rby('ps.base_speed', player_level) }} AS player_speed,
        {{ calculate_stat_rby('es.base_speed', opponent_level) }} AS opponent_speed
    FROM move_data md
    CROSS JOIN opponent_stats es
    CROSS JOIN player_stats ps
    LEFT JOIN type_eff te ON md.slot = te.slot
),

scored AS (
    SELECT
        move_name,
        move_type,
        CASE WHEN stat_used = 'Attack' THEN 'Physical' ELSE 'Special' END AS move_category,
        effectiveness,
        is_stab,
        opp_hp,
        player_speed > opponent_speed AS player_moves_first,
        CASE WHEN acc = 'N/A' THEN 100 ELSE ROUND(acc::double * 100) END AS accuracy,
        CASE WHEN is_status_move THEN 0
             ELSE {{ calculate_damage_rby(
                 'defender_stat', 'opp_hp',
                 'attacker_stat', player_level,
                 'move_name', 'acc',
                 'effectiveness', 'stab',
                 'power', 'hits'
             ) }}
        END AS expected_damage
    FROM calc
)

SELECT
    move_name,
    move_type,
    move_category,
    effectiveness,
    is_stab,
    ROUND(expected_damage, 1) AS expected_damage,
    expected_damage >= opp_hp AS will_ko,
    CASE WHEN expected_damage > 0 THEN CEIL(opp_hp / expected_damage) ELSE NULL END AS hits_to_ko,
    accuracy,
    player_moves_first,
    ROW_NUMBER() OVER (ORDER BY (expected_damage >= opp_hp) DESC, expected_damage DESC) = 1 AS recommended
FROM scored
ORDER BY will_ko DESC, expected_damage DESC

{% endmacro %}
