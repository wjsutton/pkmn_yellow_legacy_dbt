SELECT
    item_const,
    item_id,
    item_name,
    price,
    is_key_item,
    tm_number,
    tm_move,
    description
FROM {{ ref('items') }}
