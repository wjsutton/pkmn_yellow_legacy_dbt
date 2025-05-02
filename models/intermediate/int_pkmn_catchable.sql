WITH area_order as (

    SELECT 
        EAO.encounter_area,
        R.map,
        R."order"
    FROM {{ ref('stg_pkmn_encounter_area_order') }} as EAO 
    INNER JOIN {{ ref('stg_game_route_order') }} as R on R.map = EAO.map

)

, catchable_pkmn as (

    SELECT 
        EA.pokemon,
        EA.level,
        L.level_cap,
        EA.map,
        EA.area,
        CASE 
            WHEN R."order" >= EAO."order" THEN R."order" 
            ELSE EAO."order" 
        END as earliest_route
    FROM {{ ref('stg_pkmn_encounter_areas') }} as EA
    INNER JOIN {{ ref('stg_game_route_order') }} as R on R.map = EA.map
    INNER JOIN area_order as EAO on EA.area = EAO.encounter_area
    INNER JOIN {{ ref('int_game_level_cap') }} as L on R.next_gym = L.game_stage

)

SELECT
    {{ dbt_utils.generate_surrogate_key(['pokemon','level','map','area','earliest_route']) }} as id,
    pokemon,
    level,
    level_cap,
    map,
    area,
    earliest_route
FROM catchable_pkmn