{{ config(materialized='table') }}

-- Minimal time spine for MetricFlow semantic layer.
-- All semantic models use a synthetic date of 2024-01-01 since game data is static.
select cast('2024-01-01' as date) as date_day
