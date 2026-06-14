-- mart_stage_pokemon_costs: What does each pokemon cost at each game stage?
-- Pre-computes EXP costs and coverage metrics for squad optimization.
-- For each pokemon, finds the cheapest catch option per stage (highest catch level, trade bonus).

WITH game_stages AS (
    SELECT
        game_stage,
        level_cap,
        ROW_NUMBER() OVER (ORDER BY level_cap, game_stage) as stage_num
    FROM (
        SELECT DISTINCT game_stage, level_cap
        FROM {{ ref('int_pokemon_availability') }}
    )
),

-- All pokemon at all stages they're available
pokemon_at_stages AS (
    SELECT DISTINCT
        pokemon,
        initial_pokemon,
        game_stage
    FROM {{ ref('int_pokemon_availability') }}
),

-- All unique catch options with their earliest availability
catch_options AS (
    SELECT
        pa.pokemon as initial_pokemon,
        pa.encounter_level,
        CASE WHEN pa.area = 'Trade' THEN 1 ELSE 0 END as is_traded,
        MIN(gs.stage_num) as available_from_stage_num
    FROM {{ ref('int_pokemon_availability') }} pa
    INNER JOIN game_stages gs ON gs.game_stage = pa.game_stage
    WHERE pa.encounter_level IS NOT NULL
    AND pa.availability_type = 'Catchable'
    GROUP BY pa.pokemon, pa.encounter_level, pa.area
),

-- For each pokemon at each stage, evaluate all valid catch options
-- and keep only the cheapest (QUALIFY picks lowest EXP cost)
pokemon_best_option AS (
    SELECT
        pas.pokemon,
        pas.game_stage,
        gs.level_cap,
        gs.stage_num,
        co.encounter_level as catch_level,
        co.is_traded,
        CASE WHEN gs.level_cap > co.encounter_level THEN
            FLOOR(
                (exp_cap.total_exp_at_level - exp_catch.total_exp_at_level)
                / CASE WHEN co.is_traded = 1 THEN 1.5 ELSE 1.0 END
            )::integer
        ELSE 0
        END as fresh_exp_cost
    FROM pokemon_at_stages pas
    INNER JOIN game_stages gs ON gs.game_stage = pas.game_stage
    INNER JOIN catch_options co
        ON co.initial_pokemon = pas.initial_pokemon
        AND co.available_from_stage_num <= gs.stage_num
    INNER JOIN {{ ref('mart_pkmn_level_exp') }} exp_cap
        ON exp_cap.pokemon = pas.pokemon AND exp_cap.level = gs.level_cap
    INNER JOIN {{ ref('mart_pkmn_level_exp') }} exp_catch
        ON exp_catch.pokemon = pas.pokemon AND exp_catch.level = co.encounter_level
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY pas.pokemon, pas.game_stage
        ORDER BY
            CASE WHEN gs.level_cap > co.encounter_level THEN
                FLOOR(
                    (exp_cap.total_exp_at_level - exp_catch.total_exp_at_level)
                    / CASE WHEN co.is_traded = 1 THEN 1.5 ELSE 1.0 END
                )::integer
            ELSE 0
            END ASC
    ) = 1
),

-- In-game trades: to GET the species you must GIVE (and obtain) give_pokemon.
-- Evolved forms of a traded mon (e.g. trade-obtained Machoke -> Machamp) inherit
-- the same give-side requirement.
trades AS (
    SELECT get_pokemon, give_pokemon
    FROM {{ ref('stg_pkmn_trades') }}
    UNION
    SELECT e.evolution_name AS get_pokemon, t.give_pokemon
    FROM {{ ref('stg_pkmn_trades') }} t
    JOIN {{ ref('stg_pkmn_evolutions') }} e ON e.pokemon = t.get_pokemon
    WHERE e.evolution_name IS NOT NULL
),

-- The give-side mon's own cheapest catch level at each stage (reuses the
-- per-pokemon best option already computed above).
give_availability AS (
    SELECT pokemon AS give_pokemon, game_stage, catch_level AS give_catch_level
    FROM pokemon_best_option
),

-- Re-price trade picks. A traded mon is received at the LEVEL of the give-mon
-- you hand over (Gen-1 trades preserve level), so the cheapest route is to catch
-- the give-mon and trade immediately at its catch level, then raise the received
-- mon to the cap with the 1.5x traded-EXP boost. Non-trade rows pass through.
-- NOTE: the upstream QUALIFY already picked the trade option (flat cost 0) over any
-- wild option, so this re-pricing is exact except for the late game where these 8
-- species are ALSO wild-catchable (then the wild alternative isn't reconsidered here).
costs AS (
    SELECT
        pc.pokemon,
        pc.game_stage,
        pc.level_cap,
        pc.stage_num,
        CASE WHEN pc.is_traded = 1 THEN tr.give_pokemon END AS give_pokemon,
        CASE WHEN pc.is_traded = 1 AND tr.give_pokemon IS NOT NULL
             THEN ga.give_catch_level ELSE pc.catch_level END AS catch_level,
        pc.is_traded,
        CASE
            WHEN pc.is_traded = 1 AND tr.give_pokemon IS NOT NULL THEN
                CASE WHEN pc.level_cap > ga.give_catch_level THEN
                    FLOOR((exp_cap.total_exp_at_level - exp_recv.total_exp_at_level) / 1.5)::integer
                ELSE 0 END
            ELSE pc.fresh_exp_cost
        END AS fresh_exp_cost
    FROM pokemon_best_option pc
    LEFT JOIN trades tr ON tr.get_pokemon = pc.pokemon
    LEFT JOIN give_availability ga
        ON ga.give_pokemon = tr.give_pokemon AND ga.game_stage = pc.game_stage
    LEFT JOIN {{ ref('mart_pkmn_level_exp') }} exp_cap
        ON exp_cap.pokemon = pc.pokemon AND exp_cap.level = pc.level_cap
    LEFT JOIN {{ ref('mart_pkmn_level_exp') }} exp_recv
        ON exp_recv.pokemon = pc.pokemon AND exp_recv.level = ga.give_catch_level
    -- GATE: drop a trade pick whose give-mon isn't catchable/reachable by this stage.
    WHERE NOT (pc.is_traded = 1 AND tr.give_pokemon IS NOT NULL AND ga.give_catch_level IS NULL)
),

-- Growth rates
growth_data AS (
    SELECT pokemon, growth_rate
    FROM {{ ref('int_pkmn_exp_data') }}
),

-- Battle coverage summary per pokemon per stage
coverage_summary AS (
    SELECT
        game_stage,
        player_pokemon as pokemon,
        COUNT(DISTINCT trainer_pkmn_id) as total_opponents_faced,
        COUNT(DISTINCT CASE WHEN player_victory = 1 THEN trainer_pkmn_id END) as opponents_beaten,
        COUNT(DISTINCT CASE WHEN player_victory = 1 AND player_move_single_use_tm = 0 THEN trainer_pkmn_id END) as opponents_beaten_no_tm
    FROM {{ ref('mart_battle_outcomes') }}
    GROUP BY game_stage, player_pokemon
)

SELECT
    pc.pokemon,
    pc.game_stage,
    pc.level_cap,
    pc.stage_num,
    pc.catch_level,
    pc.is_traded,
    pc.give_pokemon as trade_give_pokemon,
    gd.growth_rate,
    pc.fresh_exp_cost,
    COALESCE(cs.opponents_beaten, 0) as opponents_beaten,
    COALESCE(cs.opponents_beaten_no_tm, 0) as opponents_beaten_no_tm,
    COALESCE(cs.total_opponents_faced, 0) as total_opponents_faced
FROM costs pc
INNER JOIN growth_data gd ON gd.pokemon = pc.pokemon
LEFT JOIN coverage_summary cs
    ON pc.pokemon = cs.pokemon AND pc.game_stage = cs.game_stage
