{% macro pokemon_sprite_url(col) %}
{#-
    Raw front-sprite URL for a pokemon from the Pokemon Yellow Legacy repo.
    Filenames are the lowercase species name, with three special cases:
        Nidoran-f -> nidoranf, Nidoran-m -> nidoranm, Mr-mime -> mr.mime
-#}
'https://raw.githubusercontent.com/cRz-Shadows/Pokemon_Yellow_Legacy/main/gfx/pokemon/front/'
|| CASE LOWER({{ col }})
       WHEN 'nidoran-f' THEN 'nidoranf'
       WHEN 'nidoran-m' THEN 'nidoranm'
       WHEN 'mr-mime'   THEN 'mr.mime'
       ELSE LOWER({{ col }})
   END
|| '.png'
{% endmacro %}
