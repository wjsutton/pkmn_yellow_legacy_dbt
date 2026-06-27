{% macro recommend_build(pokemon, game_stage, keep_single_use_tms=true) %}

{#
    recommend_build (catalog key: build_guide) — evolution + moveset + TM/HM plan
    for a pokemon you currently have, targeted at a game stage's level cap.

    Three sections in one tagged result (column `section`):
      'evolution' — the chain from `pokemon` to the deepest form reachable by the
                    stage (level evos must be <= level_cap; stone evos require the
                    stone be obtainable by the stage). reachable_by_cap is
                    cumulative: a step is only reachable if every prior step is.
      'moveset'   — the best <=4 damaging moves the final form can know at the
                    level cap, deduped best-per-type for coverage then filled by
                    score (power * accuracy * STAB). Spine: int_pokemon_movesets.
      'tm'        — for each recommended TM/HM move: where to get it, price, and a
                    single-use warning (single-use TMs are one-per-team).

    Variant-agnostic by design (guidance only, no run_name) — single-use TMs are
    flagged but not cross-checked against a specific team's allocation.

    Args:
        pokemon              species you have, e.g. 'Nidoran-m'
        game_stage           'Badge_1'..'Badge_8' / 'Elite 4' (sets the level cap)
        keep_single_use_tms  include single-use TM moves in the recommendation
                             (default true)

    Returns columns: section, ord, from_form, to_form, method, level_required,
                     stone, stone_location, reachable_by_cap, slot, move,
                     move_origin, move_type, move_power, is_stab, single_use_tm,
                     how_to_get, tm_or_hm, locations, price, earliest_route, warning
#}

WITH RECURSIVE

params AS (
    SELECT
        (SELECT MAX(level_cap) FROM {{ ref('int_pokemon_availability') }} WHERE game_stage = '{{ game_stage }}') AS level_cap,
        (SELECT MAX(game_order) FROM {{ ref('stg_game_route_order') }} WHERE next_gym = '{{ game_stage }}') AS stage_order
),

-- Earliest acquisition of each evolution stone (route order + where).
stone_first AS (
    SELECT
        stone_type,
        MIN(game_order)            AS stone_order,
        arg_min(map, game_order)   AS stone_map
    FROM {{ ref('stg_item_stone_locations') }}
    WHERE game_order IS NOT NULL
    GROUP BY 1
),

-- Walk the evolution chain forward from `pokemon`.
chain AS (
    SELECT 1 AS step, e.pokemon AS from_form, e.evolution_name AS to_form,
           e.evolution_level, e.evolution_stone
    FROM {{ ref('stg_pkmn_evolutions') }} e
    WHERE UPPER(e.pokemon) = UPPER('{{ pokemon }}')
      AND e.evolution_name IS NOT NULL

    UNION ALL

    SELECT c.step + 1, e.pokemon, e.evolution_name, e.evolution_level, e.evolution_stone
    FROM {{ ref('stg_pkmn_evolutions') }} e
    JOIN chain c ON e.pokemon = c.to_form
    WHERE e.evolution_name IS NOT NULL
),

steps AS (
    SELECT
        c.step,
        c.from_form,
        c.to_form,
        CASE WHEN c.evolution_level IS NOT NULL THEN 'Level' ELSE 'Stone' END AS method,
        c.evolution_level AS level_required,
        c.evolution_stone AS stone,
        sf.stone_map AS stone_location,
        CASE WHEN c.evolution_level IS NOT NULL THEN (c.evolution_level <= p.level_cap)
             ELSE (sf.stone_order IS NOT NULL AND sf.stone_order <= p.stage_order) END AS step_reachable
    FROM chain c
    CROSS JOIN params p
    LEFT JOIN stone_first sf ON sf.stone_type = c.evolution_stone
),

-- Cumulative reachability: once a step is blocked, every later step is too.
cum AS (
    SELECT *,
        MIN(CASE WHEN step_reachable THEN 1 ELSE 0 END)
            OVER (ORDER BY step ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_ok
    FROM steps
),

-- Deepest reachable form = the build target (fall back to the input species).
final_form AS (
    SELECT COALESCE(
        (SELECT to_form FROM cum WHERE cum_ok = 1 ORDER BY step DESC LIMIT 1),
        (SELECT pokemon FROM {{ ref('stg_pkmn_stats') }} WHERE UPPER(pokemon) = UPPER('{{ pokemon }}') LIMIT 1),
        '{{ pokemon }}'
    ) AS form
),

-- Candidate damaging moves for the final form, gated to the stage.
cand AS (
    SELECT
        m.move,
        m.move_origin,
        m.move_type,
        m.move_power,
        m.pkmn_level,
        m.location_details,
        CASE WHEN m.move_type = fs.type1 OR m.move_type = fs.type2 THEN true ELSE false END AS is_stab,
        COALESCE(TRY_CAST(m.move_power AS DOUBLE), 60) AS power_num,
        COALESCE(TRY_CAST(m.move_accuracy AS DOUBLE), 1.0) AS acc_num,
        m.move_origin = 'single-use-tm' AS single_use_tm
    FROM {{ ref('int_pokemon_movesets') }} m
    CROSS JOIN final_form ff
    CROSS JOIN params p
    LEFT JOIN {{ ref('stg_pkmn_stats') }} fs ON fs.pokemon = ff.form
    WHERE m.pokemon = ff.form
      AND (
          (m.move_origin = 'level-up' AND m.pkmn_level <= p.level_cap)
          OR (m.move_origin <> 'level-up' AND m.route_order <= p.stage_order)
      )
      {% if not keep_single_use_tms %}AND m.move_origin <> 'single-use-tm'{% endif %}
),

scored_moves AS (
    -- One row per move (a move can appear via several origins; keep the cheapest
    -- to obtain — level-up first, then repurchasable, then single-use).
    SELECT *,
        power_num * acc_num * (CASE WHEN is_stab THEN 1.5 ELSE 1.0 END) AS score,
        ROW_NUMBER() OVER (
            PARTITION BY move
            ORDER BY CASE move_origin WHEN 'level-up' THEN 0 WHEN 'repurchasable-tm' THEN 1 ELSE 2 END
        ) AS origin_rank
    FROM cand
),

ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY move_type ORDER BY score DESC, move) AS type_rank
    FROM scored_moves
    WHERE origin_rank = 1
),

-- Best move per type first (coverage), then fill remaining slots by score.
picked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            ORDER BY CASE WHEN type_rank = 1 THEN 0 ELSE 1 END, score DESC, move
        ) AS slot
    FROM ranked
),

build_moves AS (
    SELECT * FROM picked WHERE slot <= 4
),

-- === Assemble the three tagged sections =================================
evolution_section AS (
    SELECT
        'evolution'                AS section,
        100 + step                 AS ord,
        from_form, to_form, method,
        level_required, stone, stone_location,
        (cum_ok = 1)               AS reachable_by_cap,
        NULL::INT                  AS slot,
        NULL::VARCHAR              AS move,
        NULL::VARCHAR              AS move_origin,
        NULL::VARCHAR              AS move_type,
        NULL::VARCHAR              AS move_power,
        NULL::BOOLEAN              AS is_stab,
        NULL::BOOLEAN              AS single_use_tm,
        NULL::VARCHAR              AS how_to_get,
        NULL::VARCHAR              AS tm_or_hm,
        NULL::VARCHAR              AS locations,
        NULL::VARCHAR              AS price,
        NULL::VARCHAR              AS earliest_route,
        NULL::VARCHAR              AS warning
    FROM cum
),

moveset_section AS (
    SELECT
        'moveset'                  AS section,
        200 + bm.slot              AS ord,
        NULL::VARCHAR, NULL::VARCHAR, NULL::VARCHAR,
        NULL::INT, NULL::VARCHAR, NULL::VARCHAR,
        NULL::BOOLEAN,
        bm.slot,
        bm.move,
        bm.move_origin,
        bm.move_type,
        bm.move_power,
        bm.is_stab,
        bm.single_use_tm,
        CASE WHEN bm.move_origin = 'level-up' THEN 'Learn at Lv.' || bm.pkmn_level
             ELSE COALESCE(bm.location_details, 'TM/HM') END AS how_to_get,
        NULL::VARCHAR, NULL::VARCHAR, NULL::VARCHAR, NULL::VARCHAR, NULL::VARCHAR
    FROM build_moves bm
),

tm_section AS (
    SELECT
        'tm'                       AS section,
        300 + bm.slot              AS ord,
        NULL::VARCHAR, NULL::VARCHAR, NULL::VARCHAR,
        NULL::INT, NULL::VARCHAR, NULL::VARCHAR,
        NULL::BOOLEAN,
        NULL::INT,
        bm.move,
        bm.move_origin,
        NULL::VARCHAR, NULL::VARCHAR,
        NULL::BOOLEAN,
        bm.single_use_tm,
        NULL::VARCHAR,
        l.tm_or_hm,
        l.locations,
        l.price,
        l.earliest_nearest_route   AS earliest_route,
        CASE WHEN l.earliest_nearest_route <> l.repurchase_route
             THEN 'single-use - only one ' || (SELECT form FROM final_form) || ' per team can hold it'
             ELSE 'repurchasable - re-buyable at ' || l.repurchase_route END AS warning
    FROM build_moves bm
    JOIN {{ ref('stg_moves_tmhm_locations') }} l ON l.move = bm.move
    WHERE bm.move_origin <> 'level-up'
)

SELECT * FROM evolution_section
UNION ALL SELECT * FROM moveset_section
UNION ALL SELECT * FROM tm_section
ORDER BY ord

{% endmacro %}
