{% macro calculate_catch_cost_exp(encounter_probability, catch_rate, avg_wild_exp) %}
{#
    calculate_catch_cost_exp — acquisition cost of CATCHING a wild pokemon, in EXP-equivalent.

    Converts "time spent hunting a wild mon" into the same EXP units as fresh_exp_cost
    (the cost to RAISE a mon), so rare/hard catches stop looking free.

    Derivation (source: docs/research-encounter-rates-and-wild-exp.md):
        P(catch | met)        ~ catch_rate / 256        (full-HP / Poke Ball baseline)
        expected_battles       = 1 / [ encounter_probability * P(catch | met) ]
        catch_cost_exp         = expected_battles * avg_wild_exp_of_area

    Every wild battle fought en route is EXP a team member could have gained instead, so
    avg_wild_exp (expected wild EXP per battle in the area) is the per-battle opportunity cost.

    Args:
        encounter_probability  P(this species | an encounter happens) — el.total_probability
        catch_rate             Gen-1 0-255 capture byte (higher = easier)
        avg_wild_exp           expected wild EXP of a random battle in the area — el.avg_wild_exp

    Returns: EXP-equivalent effort to obtain one, rounded; NULL if any input is missing/zero.
#}
(
    ROUND(
        {{ avg_wild_exp }}::double * 256.0
        / NULLIF({{ encounter_probability }}::double * {{ catch_rate }}::double, 0)
    )
)
{% endmacro %}
