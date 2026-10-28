-- Clip 11.3: the statistics of Enrollment.InvoiceLine. Runs on the lab, in one session,
-- after 02a-reorganize-rebuild.sql (which rebuilt pk_InvoiceLine). A few seconds.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. Each statistic, its sample, its modifications since it was computed, and the threshold
--    of the automatic update at level 130 and above: MIN(500 + 20 % of rows, SQRT(1000 x rows)).
SELECT s.name AS statistic, s.auto_created, p.last_updated, p.rows, p.rows_sampled,
       p.modification_counter,
       CAST(IIF(500 + 0.2 * p.rows < SQRT(1000.0 * p.rows), 500 + 0.2 * p.rows,
                SQRT(1000.0 * p.rows)) AS int) AS auto_update_threshold
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Enrollment.InvoiceLine')
ORDER BY s.stats_id;
GO
-- 2. A query that filters on Label needs its statistic: past the threshold, the optimizer
--    recomputes it first, on a sample, and the query waits.
SELECT COUNT(*) AS sql_lines FROM Enrollment.InvoiceLine WHERE Label LIKE '%SQL Server%';
SELECT s.name AS statistic, p.last_updated, p.rows, p.rows_sampled, p.modification_counter
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Enrollment.InvoiceLine') AND s.name LIKE N'[_]WA[_]Sys[_]00000005%';
GO
-- 3. UPDATE STATISTICS on one table, every row read.
UPDATE STATISTICS Enrollment.InvoiceLine WITH FULLSCAN;
SELECT s.name AS statistic, p.last_updated, p.rows, p.rows_sampled, p.modification_counter
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Enrollment.InvoiceLine')
ORDER BY s.stats_id;
GO
-- 4. sp_updatestats goes through the whole database and updates every statistic with at least
--    one modification, with the default sample.
EXEC sp_updatestats;
GO
