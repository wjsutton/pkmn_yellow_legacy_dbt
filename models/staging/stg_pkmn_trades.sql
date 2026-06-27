SELECT
    get_pokemon,
    give_pokemon,
    nickname
FROM {{ ref('pkmn_trades') }}
