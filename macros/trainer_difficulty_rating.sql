{#
    trainer_difficulty_rating: categorical difficulty label for a trainer.

    Operates on the standard difficulty columns produced by the per-trainer
    aggregate CTEs (avg_battle_score, excellent_counters, good_counters).
    Pass `prefix` when those columns are qualified by a table alias, e.g.
    {{ trainer_difficulty_rating(prefix='TBD.') }}.

    Canonical definition shared by mart_team_performance, mart_recommended_teams,
    and dash_trainer_counters (previously copy-pasted in all three).
#}
{% macro trainer_difficulty_rating(prefix='') %}
    CASE
        WHEN {{ prefix }}avg_battle_score < 0.25 THEN 'Extreme'
        WHEN {{ prefix }}avg_battle_score < 0.35 THEN 'Very Hard'
        WHEN {{ prefix }}avg_battle_score < 0.5 THEN 'Hard'
        WHEN {{ prefix }}avg_battle_score < 0.65 THEN 'Medium'
        WHEN {{ prefix }}excellent_counters <= 2 AND {{ prefix }}good_counters <= 5 THEN 'Requires Specific Counter'
        ELSE 'Easy'
    END
{% endmacro %}
