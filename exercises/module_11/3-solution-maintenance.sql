-- Module 11 exercise, solution of parts 2 to 4: IndexOptimize on the accounting database, a
-- job of your own scheduled every Saturday at 22:00, and the proof. Runs on your lab, in one
-- session, after 1-start.sql (and after 2-solution-integrity.sql if you played it). It ends
-- by deleting what the exercise created: the job, the rows of dbo.CommandLog for the copy,
-- and the copy. About a minute.
USE PachadataTraining_Ex11;
SET NOCOUNT ON;
GO
-- Part 2. 1. The indexes of more than 1,000 pages, and the statistics with modifications.
SELECT OBJECT_SCHEMA_NAME(ps.object_id) + N'.' + OBJECT_NAME(ps.object_id) AS table_name,
       i.name AS index_name, ps.page_count,
       CAST(ps.avg_fragmentation_in_percent AS decimal(5,1)) AS fragmentation_pct,
       CAST(ps.avg_page_space_used_in_percent AS decimal(5,1)) AS page_density_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') AS ps
JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.index_level = 0 AND ps.page_count > 1000 AND i.type IN (1, 2)
  AND ps.avg_fragmentation_in_percent > 5
ORDER BY table_name;
SELECT OBJECT_SCHEMA_NAME(s.object_id) + N'.' + OBJECT_NAME(s.object_id) AS table_name,
       s.name AS statistic, p.rows, p.rows_sampled, p.modification_counter
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE p.modification_counter > 0 AND OBJECTPROPERTY(s.object_id, 'IsMSShipped') = 0
ORDER BY table_name, statistic;
GO
-- 2. IndexOptimize with its defaults, plus the statistics that changed.
USE DBA;
EXECUTE dbo.IndexOptimize
    @Databases = N'PachadataTraining_Ex11',
    @UpdateStatistics = N'ALL',
    @OnlyModifiedStatistics = N'Y',
    @LogToTable = N'Y';
GO
-- 3. Each decision, with the size and fragmentation it was based on.
SELECT ObjectName, IndexName, StatisticsName, CommandType,
       ExtendedInfo.value('(ExtendedInfo/PageCount)[1]', 'int') AS page_count,
       ExtendedInfo.value('(ExtendedInfo/Fragmentation)[1]', 'decimal(5,1)') AS fragmentation_pct,
       LEFT(Command, 120) AS command, ErrorNumber
FROM dbo.CommandLog
WHERE DatabaseName = N'PachadataTraining_Ex11' AND CommandType IN (N'ALTER_INDEX', N'UPDATE_STATISTICS')
ORDER BY ID;
GO
-- 4. The indexes after IndexOptimize.
USE PachadataTraining_Ex11;
SELECT OBJECT_SCHEMA_NAME(ps.object_id) + N'.' + OBJECT_NAME(ps.object_id) AS table_name,
       i.name AS index_name, ps.page_count,
       CAST(ps.avg_fragmentation_in_percent AS decimal(5,1)) AS fragmentation_pct,
       CAST(ps.avg_page_space_used_in_percent AS decimal(5,1)) AS page_density_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') AS ps
JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.index_level = 0 AND ps.page_count > 500 AND i.type = 1
ORDER BY table_name;
GO
-- Part 3. 1. A job of its own for the accounting database, run in DBA: step 1 checks the
--    database and stops the job if it fails (the default), step 2 maintains its indexes and
--    statistics. Every Saturday at 22:00 (freq_type 8, weekly; freq_interval 64, Saturday).
USE msdb;
IF EXISTS (SELECT * FROM dbo.sysjobs WHERE name = N'Exercise 11 - accounting maintenance')
    EXEC dbo.sp_delete_job @job_name = N'Exercise 11 - accounting maintenance', @delete_unused_schedule = 1;
EXEC dbo.sp_add_job @job_name = N'Exercise 11 - accounting maintenance', @owner_login_name = N'sa';
EXEC dbo.sp_add_jobstep
    @job_name = N'Exercise 11 - accounting maintenance', @step_name = N'Integrity',
    @subsystem = N'TSQL', @database_name = N'DBA', @on_success_action = 3,
    @command = N'EXECUTE dbo.DatabaseIntegrityCheck @Databases = ''PachadataTraining_Ex11'',
@NoInformationalMessages = ''Y'', @LogToTable = ''Y'';';
EXEC dbo.sp_add_jobstep
    @job_name = N'Exercise 11 - accounting maintenance', @step_name = N'Indexes and statistics',
    @subsystem = N'TSQL', @database_name = N'DBA',
    @command = N'EXECUTE dbo.IndexOptimize @Databases = ''PachadataTraining_Ex11'',
@UpdateStatistics = ''ALL'', @OnlyModifiedStatistics = ''Y'', @LogToTable = ''Y'';';
EXEC dbo.sp_add_jobschedule
    @job_name = N'Exercise 11 - accounting maintenance', @name = N'Exercise 11 - Saturday at 22:00',
    @freq_type = 8, @freq_interval = 64, @freq_recurrence_factor = 1, @active_start_time = 220000;
EXEC dbo.sp_add_jobserver @job_name = N'Exercise 11 - accounting maintenance';
SELECT sc.name AS schedule_name, sc.freq_type, sc.freq_interval, sc.active_start_time
FROM dbo.sysschedules AS sc
WHERE sc.name = N'Exercise 11 - Saturday at 22:00';
GO
-- 2. Started by hand, then its history. The last row of CommandLog before the job is kept,
--    to read only what the job did.
DROP TABLE IF EXISTS #before_job;
SELECT MAX(ID) AS last_id INTO #before_job FROM DBA.dbo.CommandLog;
EXEC msdb.dbo.sp_start_job @job_name = N'Exercise 11 - accounting maintenance';
WAITFOR DELAY '00:00:40';
SELECT h.step_id, h.step_name, h.run_status, h.run_duration, LEFT(h.message, 80) AS message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Exercise 11 - accounting maintenance'
ORDER BY h.instance_id;
GO
-- Part 4. The proof: what the job's run wrote in CommandLog, the date of the last good check,
-- and the job with its schedule and its last outcome.
SELECT CommandType, COUNT(*) AS commands, SUM(IIF(ErrorNumber <> 0, 1, 0)) AS failed
FROM DBA.dbo.CommandLog
WHERE DatabaseName = N'PachadataTraining_Ex11' AND ID > (SELECT last_id FROM #before_job)
GROUP BY CommandType;
SELECT DATABASEPROPERTYEX(N'PachadataTraining_Ex11', 'LastGoodCheckDbTime') AS last_good_checkdb;
SELECT j.name AS job_name, sc.name AS schedule_name, sv.last_run_outcome
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobservers AS sv ON sv.job_id = j.job_id
JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules AS sc ON sc.schedule_id = js.schedule_id
WHERE j.name = N'Exercise 11 - accounting maintenance';
GO
-- Cleanup: the job and its schedule, the rows of CommandLog, the copy.
EXEC msdb.dbo.sp_delete_job @job_name = N'Exercise 11 - accounting maintenance', @delete_unused_schedule = 1;
DELETE FROM DBA.dbo.CommandLog WHERE DatabaseName = N'PachadataTraining_Ex11';
DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'PachadataTraining_Ex11');
ALTER DATABASE PachadataTraining_Ex11 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining_Ex11;
GO
SELECT name FROM sys.databases WHERE name = N'PachadataTraining_Ex11';
SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'Exercise 11%';
GO
