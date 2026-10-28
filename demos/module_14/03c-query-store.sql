-- Clip 14.3: the Query Store of PachadataTraining, in one sequence. Runs on the lab, in one
-- session, after 03b-long-queries.sql (without it, the top of the list is another query,
-- which is not an error). It only reads.
-- 1. Its state: an actual state different from the desired one is a problem
--    (READ_ONLY when the store is full).
-- 2. The five queries that used the most CPU in the last 24 hours. The statistics are
--    averages per interval: the totals are weighted by the number of executions, and the
--    times are in microseconds.
-- The module 4 of the course sqlserver-optimisation, "Le Query Store", goes further:
-- regressions, plan forcing, hints.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The state of the store.
SELECT actual_state_desc, desired_state_desc, readonly_reason,
       current_storage_size_mb, max_storage_size_mb,
       query_capture_mode_desc, interval_length_minutes
FROM sys.database_query_store_options;
GO
-- 2. The most expensive queries, by CPU.
SELECT TOP (5) q.query_id,
       SUM(rs.count_executions) AS executions,
       CAST(SUM(rs.avg_cpu_time * rs.count_executions) / 1000.0 AS decimal(12, 0)) AS cpu_total_ms,
       CAST(SUM(rs.avg_duration * rs.count_executions)
            / SUM(rs.count_executions) / 1000.0 AS decimal(12, 1)) AS avg_duration_ms,
       CAST(SUM(rs.avg_logical_io_reads * rs.count_executions)
            / SUM(rs.count_executions) AS decimal(12, 0)) AS avg_reads,
       COUNT(DISTINCT p.plan_id) AS plans,
       LEFT(REPLACE(REPLACE(t.query_sql_text, CHAR(13), N''), CHAR(10), N' '), 60) AS query_text
FROM sys.query_store_runtime_stats AS rs
JOIN sys.query_store_runtime_stats_interval AS i
  ON i.runtime_stats_interval_id = rs.runtime_stats_interval_id
JOIN sys.query_store_plan AS p ON p.plan_id = rs.plan_id
JOIN sys.query_store_query AS q ON q.query_id = p.query_id
JOIN sys.query_store_query_text AS t ON t.query_text_id = q.query_text_id
WHERE i.start_time >= DATEADD(HOUR, -24, SYSUTCDATETIME())
GROUP BY q.query_id, t.query_sql_text
ORDER BY cpu_total_ms DESC;
