-- recommend_build (catalog key: build_guide) — example invocation.
-- The query logic lives in the recommend_build() macro so it is reusable and
-- callable with parameters (e.g. by the agent via `dbt show --inline`, or the
-- fast-path build_fast.build_guide()). This analysis is a runnable example.
--
-- OUTPUT: one tagged table (section = 'evolution' | 'moveset' | 'tm') giving the
--         evolution plan, recommended moveset, and TM/HM acquisition plan.
--
-- Example: a Nidoran-m being built for Misty (Badge_2).

{{ recommend_build(
    pokemon='Nidoran-m',
    game_stage='Badge_2',
    keep_single_use_tms=true
) }}
