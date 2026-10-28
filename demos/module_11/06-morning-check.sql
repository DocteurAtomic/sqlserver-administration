-- Clip 11.5, end: the morning check. Runs on the lab, in one session, at any time.
-- Reads only: the maintenance commands of the last 24 hours that failed, the date of the last
-- good integrity check of each database, and the last run of the maintenance jobs.
USE DBA;
SET NOCOUNT ON;
GO
-- 1. The commands that failed in the last 24 hours. No row: the night went well.
SELECT DatabaseName, CommandType, ObjectName, IndexName, StartTime, ErrorNumber,
       LEFT(ErrorMessage, 200) AS error_message
FROM dbo.CommandLog
WHERE StartTime > DATEADD(HOUR, -24, SYSDATETIME()) AND ErrorNumber <> 0
ORDER BY ID;
GO
-- 2. Each database and its last good integrity check: older than a day is an alert.
SELECT name, DATABASEPROPERTYEX(name, 'LastGoodCheckDbTime') AS last_good_checkdb,
       DATEDIFF(HOUR, CAST(DATABASEPROPERTYEX(name, 'LastGoodCheckDbTime') AS datetime),
                SYSDATETIME()) AS hours_ago
FROM sys.databases
WHERE database_id <> 2
ORDER BY name;
GO
-- 3. The maintenance jobs, their schedule and their last run (outcome 1: succeeded). No
--    schedule: nothing runs.
SELECT j.name AS job_name, sc.name AS schedule_name, sv.last_run_date, sv.last_run_time,
       sv.last_run_outcome
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobservers AS sv ON sv.job_id = j.job_id
LEFT JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules AS sc ON sc.schedule_id = js.schedule_id
WHERE j.name LIKE N'DatabaseIntegrityCheck%' OR j.name LIKE N'IndexOptimize%'
ORDER BY j.name;
GO
