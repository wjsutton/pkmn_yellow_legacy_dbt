{#
    trainer_difficulty_score: numeric difficulty weight for a trainer (rounded to 1dp).

    Operates on the standard difficulty columns from the per-trainer aggregate
    CTEs: avg_battle_score, excellent_counters, good_counters, is_mini_boss,
    tm_dependent_solutions, natural_solutions, and min_battle_score. The CTE must
    therefore expose MIN(battle_score) AS min_battle_score.

    Pass `prefix` when those columns are qualified by a table alias, e.g.
    {{ trainer_difficulty_score(prefix='TBD.') }}.

    Canonical definition shared by mart_team_performance, mart_recommended_teams,
    and dash_trainer_counters. Includes the min_battle_score penalty (+1 when a
    trainer has a near-unwinnable matchup) in all three; this term had previously
    drifted into mart_team_performance only.
#}
{% macro trainer_difficulty_score(prefix='') %}
    ROUND(
        (
            (1 - {{ prefix }}avg_battle_score) * 4
            + CASE WHEN {{ prefix }}excellent_counters = 0 THEN 2 ELSE 0 END
            + CASE WHEN {{ prefix }}good_counters <= 2 THEN 1 ELSE 0 END
            + CASE WHEN {{ prefix }}is_mini_boss = 1 THEN 1 ELSE 0 END
            + CASE WHEN {{ prefix }}tm_dependent_solutions > {{ prefix }}natural_solutions THEN 1 ELSE 0 END
            + CASE WHEN {{ prefix }}min_battle_score < 0.2 THEN 1 ELSE 0 END
        ), 1
    )
{% endmacro %}
