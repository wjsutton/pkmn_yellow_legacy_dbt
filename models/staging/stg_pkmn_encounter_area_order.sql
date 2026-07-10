SELECT
    {{ dbt_utils.generate_surrogate_key(['area']) }} as id,
    area,
    encounter_method,
    tile_type,
    required_badge_count,
    required_item,
    area_order,
    representative_location
FROM {{ ref('pkmn_encounter_area_order') }}
