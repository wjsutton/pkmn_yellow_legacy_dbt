{% macro greedy_pick_round(round_num, coverage_cte) %}
{%- set prev_picks = 'all_picks_thru_' ~ (round_num - 1) if round_num > 1 else 'initial_picks' -%}
{%- set prev_covered = 'covered_thru_' ~ (round_num - 1) if round_num > 1 else 'initial_covered' -%}

round_{{ round_num }}_scored AS (
    SELECT
        c.game_stage,
        c.run_name,
        c.pokemon,
        c.exp_cost,
        COUNT(DISTINCT c.trainer_pkmn_id) as new_coverage,
        ROW_NUMBER() OVER (
            PARTITION BY c.game_stage, c.run_name
            ORDER BY
                COUNT(DISTINCT c.trainer_pkmn_id)::FLOAT / GREATEST(1, c.exp_cost) DESC,
                COUNT(DISTINCT c.trainer_pkmn_id) DESC,
                c.exp_cost ASC
        ) as pick_rank
    FROM {{ coverage_cte }} c
    WHERE c.player_victory = 1
    AND NOT EXISTS (
        SELECT 1 FROM {{ prev_picks }} pp
        WHERE pp.game_stage = c.game_stage AND pp.run_name = c.run_name AND pp.pokemon = c.pokemon
    )
    AND NOT EXISTS (
        SELECT 1 FROM {{ prev_covered }} pc
        WHERE pc.game_stage = c.game_stage AND pc.run_name = c.run_name AND pc.trainer_pkmn_id = c.trainer_pkmn_id
    )
    GROUP BY c.game_stage, c.run_name, c.pokemon, c.exp_cost
    HAVING COUNT(DISTINCT c.trainer_pkmn_id) > 0
),

pick_{{ round_num }} AS (
    SELECT game_stage, run_name, pokemon, exp_cost, new_coverage
    FROM round_{{ round_num }}_scored
    WHERE pick_rank = 1
),

covered_thru_{{ round_num }} AS (
    SELECT game_stage, run_name, trainer_pkmn_id FROM {{ prev_covered }}
    UNION
    SELECT DISTINCT c.game_stage, c.run_name, c.trainer_pkmn_id
    FROM {{ coverage_cte }} c
    INNER JOIN pick_{{ round_num }} p
        ON c.game_stage = p.game_stage AND c.run_name = p.run_name AND c.pokemon = p.pokemon
    WHERE c.player_victory = 1
),

all_picks_thru_{{ round_num }} AS (
    SELECT game_stage, run_name, pokemon, exp_cost, new_coverage FROM {{ prev_picks }}
    UNION ALL
    SELECT game_stage, run_name, pokemon, exp_cost, new_coverage FROM pick_{{ round_num }}
)
{% endmacro %}
