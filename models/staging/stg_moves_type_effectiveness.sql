
SELECT 
    {{ dbt_utils.generate_surrogate_key(['attacking_type','defending_type']) }} as id,
    attacking_type,
    defending_type,
    damage_modifier
FROM {{ ref('moves_type_effectiveness') }}