{% macro collapse_evolution_chains(source_cte, pokemon_col, game_stage_col) %}
-- Maps each pokemon to its base form and evolution depth
_evo_base_form AS (
    SELECT
        evo.pokemon,
        -- e1 = row where this pokemon is the evolution (i.e. parent)
        -- e2 = row where e1's parent is the evolution (i.e. grandparent)
        COALESCE(e2.pokemon, e1.pokemon, evo.pokemon) as base_form,
        CASE
            WHEN e2.pokemon IS NOT NULL THEN 2  -- grandparent exists = 2nd evo
            WHEN e1.pokemon IS NOT NULL THEN 1  -- parent exists = 1st evo
            ELSE 0                               -- no parent = base form
        END as evo_depth
    FROM {{ ref('stg_pkmn_evolutions') }} evo
    -- e1: who evolves INTO this pokemon?
    LEFT JOIN {{ ref('stg_pkmn_evolutions') }} e1
        ON e1.evolution_name = evo.pokemon
    -- e2: who evolves INTO e1? (grandparent)
    LEFT JOIN {{ ref('stg_pkmn_evolutions') }} e2
        ON e2.evolution_name = e1.pokemon
),

-- Human-readable evolution notes
_evo_notes AS (
    SELECT
        evo.pokemon,
        CASE
            -- 2-stage: direct evolution from parent
            WHEN ebf.evo_depth = 1 THEN
                'evolve from ' || e1.pokemon ||
                CASE
                    WHEN e1.evolution_stone IS NOT NULL THEN ' with ' || e1.evolution_stone || ' Stone'
                    WHEN e1.evolution_level IS NOT NULL THEN ' at Lv.' || e1.evolution_level
                    ELSE ''
                END
            -- 3-stage: full chain description
            WHEN ebf.evo_depth = 2 THEN
                'evolve from ' || e2.pokemon || ' (' ||
                CASE
                    WHEN e2.evolution_stone IS NOT NULL THEN e2.evolution_stone || ' Stone'
                    WHEN e2.evolution_level IS NOT NULL THEN 'Lv.' || e2.evolution_level
                    ELSE ''
                END ||
                ' → ' || e1.pokemon || ') + ' ||
                CASE
                    WHEN e1.evolution_stone IS NOT NULL THEN e1.evolution_stone || ' Stone'
                    WHEN e1.evolution_level IS NOT NULL THEN 'Lv.' || e1.evolution_level
                    ELSE ''
                END
            ELSE NULL  -- base forms get no note
        END as evolution_note
    FROM {{ ref('stg_pkmn_evolutions') }} evo
    INNER JOIN _evo_base_form ebf ON ebf.pokemon = evo.pokemon
    -- e1: parent (who evolves into this pokemon)
    LEFT JOIN {{ ref('stg_pkmn_evolutions') }} e1
        ON e1.evolution_name = evo.pokemon
    -- e2: grandparent (who evolves into e1)
    LEFT JOIN {{ ref('stg_pkmn_evolutions') }} e2
        ON e2.evolution_name = e1.pokemon
    WHERE ebf.evo_depth > 0
),

-- Keep only the most evolved form per chain per game stage
{{ source_cte }}_deduped AS (
    SELECT src.*
    FROM {{ source_cte }} src
    INNER JOIN _evo_base_form ebf ON ebf.pokemon = src.{{ pokemon_col }}
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY src.{{ game_stage_col }}, ebf.base_form
        ORDER BY ebf.evo_depth DESC
    ) = 1
),
{% endmacro %}
