-- ci: skip (two sessions: run 02b-resumable-session1.sql first)
-- Clip 11.2, end: a resumable online rebuild, paused from a second session.
-- Session 2. Runs on the lab, while 02b-resumable-session1.sql is running.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The operation in progress, then paused.
SELECT name, state_desc, CAST(percent_complete AS decimal(5,1)) AS percent_complete, page_count
FROM sys.index_resumable_operations;
ALTER INDEX pk_Activity ON Elearning.Activity PAUSE;
WAITFOR DELAY '00:00:01';
SELECT name, state_desc, CAST(percent_complete AS decimal(5,1)) AS percent_complete,
       page_count, last_pause_time
FROM sys.index_resumable_operations;
GO
-- 2. During the pause, the table stays writable: both copies of the index are maintained.
UPDATE TOP (1000) Elearning.Activity SET EventTime = EventTime;
SELECT @@ROWCOUNT AS rows_updated_during_pause;
GO
-- 3. RESUME starts again from where the operation stopped.
DECLARE @t datetime2 = SYSDATETIME();
ALTER INDEX pk_Activity ON Elearning.Activity RESUME;
SELECT DATEDIFF(millisecond, @t, SYSDATETIME()) AS resume_ms;
SELECT COUNT(*) AS operations_left FROM sys.index_resumable_operations;
-- A resumable rebuild samples the statistic of its index.
SELECT p.last_updated, p.rows, p.rows_sampled
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.object_id = OBJECT_ID(N'Elearning.Activity') AND s.name = N'pk_Activity';
GO
