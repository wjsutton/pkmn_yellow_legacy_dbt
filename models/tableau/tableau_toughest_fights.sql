SELECT 
    id,
    run,
    game_stage,
    trainer_pkmn_id,
    player_pkmn_id,
    trainer,
    trainer_pokemon,
    player_pokemon,
    player_pkmn_move,
    player_pkmn_move_origin,
    {{ fetch_sprite(name = trainer, type = 'trainer', face='front') }} as trainer_sprite,
    {{ fetch_sprite(name = trainer_pokemon, type = 'pokemon', face='front') }} as trainer_pokemon_sprite,
    {{ fetch_sprite(name = player_pokemon, type = 'pokemon', face='front') }} as player_pokemon_sprite
FROM {{ ref('int_battle_analysis') }}