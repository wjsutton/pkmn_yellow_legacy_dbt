{% macro trainer_sprite_url(trainer) %}
{#-
    Raw trainer-sprite URL from the Pokemon Yellow Legacy repo. Sprites are keyed by
    trainer CLASS, not the per-instance trainer id, so we resolve the class first:
      1. Named bosses / rival / champion / NPCs -> explicit (ordered) matches.
      2. Generic trainers '<Location>_<Class>_<n>' -> strip prefix+number, normalise.
    Gendered classes (Jr Trainer, Cooltrainer) default to the male sprite -- the source
    rosters don't carry gender, so flip these in the data if a portrait looks wrong.
    Unmapped trainers return NULL (no sprite).
-#}
'https://raw.githubusercontent.com/cRz-Shadows/Pokemon_Yellow_Legacy/main/gfx/trainers/'
|| CASE
    -- Gym leaders / Elite Four / special named trainers
    WHEN {{ trainer }} LIKE 'Brock%'        THEN 'brock'
    WHEN {{ trainer }} LIKE 'Misty%'        THEN 'misty'
    WHEN {{ trainer }} LIKE 'Lt._Surge%'    THEN 'lt.surge'
    WHEN {{ trainer }} LIKE 'Erika%' OR {{ trainer }} LIKE 'Erica%' THEN 'erika'
    WHEN {{ trainer }} LIKE 'Koga%'         THEN 'koga'
    WHEN {{ trainer }} LIKE '%Janine%'      THEN 'janine'
    WHEN {{ trainer }} LIKE 'Sabrina%'      THEN 'sabrina'
    WHEN {{ trainer }} LIKE 'Blaine%'       THEN 'blaine'
    WHEN {{ trainer }} LIKE 'Giovanni%'     THEN 'giovanni'
    WHEN {{ trainer }} LIKE 'Lorelei%'      THEN 'lorelei'
    WHEN {{ trainer }} LIKE 'Bruno%'        THEN 'bruno'
    WHEN {{ trainer }} LIKE 'Agatha%'       THEN 'agatha'
    WHEN {{ trainer }} LIKE 'Lance%'        THEN 'lance'
    -- Rival appearances: phases 1-3 / 4-5 / 6-7 + Champion map to rival1/2/3
    WHEN {{ trainer }} LIKE 'Champion%'     THEN 'rival3'
    WHEN {{ trainer }} LIKE 'Rival_1%' OR {{ trainer }} LIKE 'Rival_2%' OR {{ trainer }} LIKE 'Rival_3%' THEN 'rival1'
    WHEN {{ trainer }} LIKE 'Rival_4%' OR {{ trainer }} LIKE 'Rival_5%' THEN 'rival2'
    WHEN {{ trainer }} LIKE 'Rival_6%' OR {{ trainer }} LIKE 'Rival_7%' THEN 'rival3'
    WHEN {{ trainer }} LIKE 'Professor_Oak%' THEN 'prof.oak'
    WHEN {{ trainer }} LIKE 'Nurse_Joy%'    THEN 'joy'
    WHEN {{ trainer }} LIKE 'Officer_Jenny%' THEN 'jenny'
    WHEN {{ trainer }} LIKE 'Jessie_&_James%' THEN 'jessiejames'
    -- Bonus trainers added by the romhack -> their own in-battle pic (per data/trainers/pic_pointers_money.asm)
    WHEN {{ trainer }} LIKE 'Craig%'  THEN 'chris'   -- CRAIG  ($1B) -> PKMNTrainerMPic
    WHEN {{ trainer }} LIKE 'Weebra%' THEN 'kris'    -- WEEBRA ($30) -> PKMNTrainerFPic
    WHEN {{ trainer }} LIKE 'Smith%'  THEN 'fisher'  -- SMITH  ($0D) -> FisherPic
    -- Class catches for odd suffixes (Rocket_6_Lift_Key, Dojo_Master, ...)
    WHEN {{ trainer }} LIKE '%Rocket%' THEN 'rocket'
    WHEN {{ trainer }} LIKE '%Dojo%'   THEN 'blackbelt'
    -- Generic trainers: strip location prefix + trailing number, keep letters only
    ELSE CASE LOWER(REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(
            {{ trainer }}, '^[A-Za-z0-9]+_', ''), '_[0-9]+$', ''), '[^A-Za-z]', '', 'g'))
        WHEN 'bugcatcher'  THEN 'bugcatcher'
        WHEN 'jrtrainer'   THEN 'jr.trainerm'
        WHEN 'lass'        THEN 'lass'
        WHEN 'youngster'   THEN 'youngster'
        WHEN 'swimmer'     THEN 'swimmer'
        WHEN 'hiker'       THEN 'hiker'
        WHEN 'supernerd'   THEN 'supernerd'
        WHEN 'fossilnerd'  THEN 'supernerd'
        WHEN 'rocket'      THEN 'rocket'
        WHEN 'nuggetrocket' THEN 'rocket'
        WHEN 'beauty'      THEN 'beauty'
        WHEN 'burglar'     THEN 'burglar'
        WHEN 'cueball'     THEN 'cueball'
        WHEN 'fisher'      THEN 'fisher'
        WHEN 'fisherman'   THEN 'fisher'
        WHEN 'juggler'     THEN 'juggler'
        WHEN 'tamer'       THEN 'tamer'
        WHEN 'channeler'   THEN 'channeler'
        WHEN 'gambler'     THEN 'gambler'
        WHEN 'gentleman'   THEN 'gentleman'
        WHEN 'gentlemen'   THEN 'gentleman'
        WHEN 'sailor'      THEN 'sailor'
        WHEN 'engineer'    THEN 'engineer'
        WHEN 'biker'       THEN 'biker'
        WHEN 'birdkeeper'  THEN 'birdkeeper'
        WHEN 'cooltrainer' THEN 'cooltrainerm'
        WHEN 'blackbelt'   THEN 'blackbelt'
        WHEN 'dojo'        THEN 'blackbelt'
        WHEN 'psychic'     THEN 'psychic'
        WHEN 'scientist'   THEN 'scientist'
        WHEN 'pokmaniac'   THEN 'pokemaniac'
        WHEN 'pokemaniac'  THEN 'pokemaniac'
        WHEN 'rocker'      THEN 'rocker'
        ELSE NULL
    END
END || '.png'
{% endmacro %}
