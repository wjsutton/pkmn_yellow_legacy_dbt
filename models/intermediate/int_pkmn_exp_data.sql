WITH pkmn_with_exp_data AS (
    SELECT 
        s.pokedex,
        s.pokemon,
        s.hp,
        s.attack,
        s.defence,
        s.special,
        s.speed,
        s.total,
        s.type1,
        s.type2,
        gr.growth_rate,
        be.base_exp
    FROM {{ ref('stg_pkmn_stats') }} s
    LEFT JOIN {{ ref('stg_pkmn_growth_rates') }} gr
        ON s.pokedex = gr.pokedex
    LEFT JOIN {{ ref('stg_pkmn_base_exp') }} be
        ON s.pokedex = be.pokedex
)

SELECT
    pokedex,
    pokemon,
    hp,
    attack,
    defence,
    special,
    speed,
    total,
    type1,
    type2,
    growth_rate,
    base_exp,
    {{ calculate_total_exp_for_level('100', 'growth_rate') }} AS max_exp_to_100
FROM pkmn_with_exp_data
