{#
    is_legendary: single source of truth for the Gen-1 legendary roster.

    Returns a boolean SQL expression that is TRUE when the given column holds a
    legendary species. Use it both as a flag and as a filter:

        CASE WHEN {{ is_legendary('player_pokemon') }} THEN 1 ELSE 0 END  -- flag
        WHERE no_legends = 0 OR NOT {{ is_legendary('player_pokemon') }}   -- filter

    The list previously lived hardcoded in 8 places (4 models + 4 analyses);
    centralising it here means a new legendary is a one-line change.
#}
{% macro is_legendary(pokemon_column) %}
    ({{ pokemon_column }} IN ('Moltres', 'Articuno', 'Zapdos', 'Mewtwo', 'Mew'))
{% endmacro %}
