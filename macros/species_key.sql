{#
    species_key: canonical, join-safe key for a species name.

    Upper-cased and stripped of every non-alphanumeric character, so all the
    string forms of a species collapse to one stable key:

        'Nidoran-m' -> 'NIDORANM'
        'Mr-mime'   -> 'MRMIME'
        'Farfetchd' -> 'FARFETCHD'

    Purpose: kill the string-surgery join bug class (issue #17). The DB stores
    hyphenated/spaced species names; every consumer (esp. the dbtPlaysPokemon
    agent) used to invent its own .replace()/REPLACE()/capitalize normalisation,
    some of them wrong. Emit this key once on the boundary tables the agent reads
    and callers bind the raw emulator value through the same rule -- no surgery.

        {{ species_key('pokemon') }} AS species_key
#}
{% macro species_key(pokemon_column) %}
    UPPER(REGEXP_REPLACE({{ pokemon_column }}, '[^A-Za-z0-9]', '', 'g'))
{% endmacro %}
