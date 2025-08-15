WITH level_range AS (
    SELECT seq4() + 1 AS pkmn_level
    FROM TABLE(generator(rowcount => 100))
),

pokemon_base_stats AS (
    SELECT 
        pokedex,
        pokemon,
        hp,
        attack,
        defense,
        special,
        speed,
        type1,
        type2
    FROM {{ ref('stg_pkmn_stats') }}
),

pokemon_calculated_stats AS (
    SELECT 
        {{ dbt_utils.generate_surrogate_key(['P.pokedex','L.pkmn_level']) }} as id,
        P.pokedex,
        P.pokemon,
        L.pkmn_level,
        P.type1,
        P.type2,
        -- Calculate Generation 1 stats using existing macros
        {{ calculate_hp_rby('P.hp','L.pkmn_level','7') }} as calculated_hp,
        {{ calculate_stat_rby('P.attack','L.pkmn_level','7') }} as calculated_attack,
        {{ calculate_stat_rby('P.defense','L.pkmn_level','7') }} as calculated_defense,
        {{ calculate_stat_rby('P.special','L.pkmn_level','7') }} as calculated_special,
        {{ calculate_stat_rby('P.speed','L.pkmn_level','7') }} as calculated_speed,
        -- Include base stats for reference
        P.hp as base_hp,
        P.attack as base_attack,
        P.defense as base_defense,
        P.special as base_special,
        P.speed as base_speed
    FROM pokemon_base_stats P
    CROSS JOIN level_range L
)

SELECT 
    id,
    pokedex,
    pokemon,
    pkmn_level,
    type1,
    type2,
    calculated_hp,
    calculated_attack,
    calculated_defense,
    calculated_special,
    calculated_speed,
    base_hp,
    base_attack,
    base_defense,
    base_special,
    base_speed,
    -- Add total calculated stats for convenience
    calculated_hp + calculated_attack + calculated_defense + calculated_special + calculated_speed as calculated_total
FROM pokemon_calculated_stats