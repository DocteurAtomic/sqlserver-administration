-- Module 14, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It gives the instance back as setup/install.sh left it, and takes a second:
-- 1. Drops the event session LongQueries, the server trigger DatabaseChanges and its table
--    DBA.dbo.DatabaseChangeLog, the job "Module 14 - Nightly export", and sp_WhoIsActive:
--    the lab goes back to its base state (DBA with Ola Hallengren's scripts and their
--    jobs). On a production instance, sp_WhoIsActive stays.
-- 2. Turns the global trace flag 3226 off.
-- 3. Deletes the backup file of 01c-cycle-logs.sql, if it is still there, and drops the copy
--    of the exercise, PachadataTraining_Ex14, if the exercise was left half-way.
-- What T-SQL cannot undo:
--   - the .xel files of LongQueries stay in /var/opt/mssql/log:
--       docker exec sqladmcourse sh -c 'rm -f /var/opt/mssql/log/LongQueries_*.xel'
--   - the settings of 01d-startup-settings.sh, if you ran it on your lab:
--       ENGINE=docker ./demos/module_14/01d-startup-settings.sh off
--   - the recycled error logs stay archives; they age out by themselves;
--   - the empty folder /var/opt/mssql/backup/module_14 of 01c-cycle-logs.sql:
--       docker exec sqladmcourse rmdir /var/opt/mssql/backup/module_14
-- The database trigger and its table live in PachadataTraining, which the next module's
-- 00-setup.sql restores.
USE master;
SET NOCOUNT ON;
GO
-- 1. The objects of the module.
IF EXISTS (SELECT * FROM sys.server_event_sessions WHERE name = N'LongQueries')
    DROP EVENT SESSION LongQueries ON SERVER;
IF EXISTS (SELECT * FROM sys.server_triggers WHERE name = N'DatabaseChanges')
    DROP TRIGGER DatabaseChanges ON ALL SERVER;
IF OBJECT_ID(N'DBA.dbo.DatabaseChangeLog') IS NOT NULL
    DROP TABLE DBA.dbo.DatabaseChangeLog;
IF OBJECT_ID(N'DBA.dbo.sp_WhoIsActive') IS NOT NULL
    EXEC (N'USE DBA; DROP PROCEDURE dbo.sp_WhoIsActive;');
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'Module 14 - Nightly export')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Module 14 - Nightly export';
GO
-- 2. The trace flag.
DBCC TRACEOFF (3226, -1) WITH NO_INFOMSGS;
GO
-- 3. The backup file, and the copy of the exercise.
IF EXISTS (SELECT * FROM sys.dm_os_file_exists(N'/var/opt/mssql/backup/module_14/DBA.bak')
           WHERE file_exists = 1)
    EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_14/DBA.bak';
IF DB_ID(N'PachadataTraining_Ex14') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataTraining_Ex14 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataTraining_Ex14;
END;
GO
-- What is left of the module: nothing.
SELECT (SELECT COUNT(*) FROM sys.server_event_sessions WHERE name = N'LongQueries') AS event_sessions,
       (SELECT COUNT(*) FROM sys.server_triggers WHERE name = N'DatabaseChanges') AS server_triggers,
       (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name LIKE N'Module 14%' OR name LIKE N'Exercise 14%') AS jobs,
       CASE WHEN OBJECT_ID(N'DBA.dbo.sp_WhoIsActive') IS NULL THEN 0 ELSE 1 END AS sp_whoisactive,
       (SELECT COUNT(*) FROM msdb.dbo.sysjobs) AS all_jobs;
