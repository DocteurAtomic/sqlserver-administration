-- Module 11, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It gives the instance back as setup/install.sh left it, and takes a few seconds:
-- 1. Removes the two schedules of 05-schedule-maintenance.sql, gives the integrity and index
--    jobs of the user databases back their command as setup/install-ola.sh created it, and
--    purges the history of the three jobs.
--    DBA, its jobs and dbo.CommandLog belong to the lab and stay.
-- 2. Drops IntegrityDemo if 01b-damaged-page.sql was stopped before its end.
-- 3. Deletes the backup files of 02a-reorganize-rebuild.sql and the backup history of
--    PachadataTraining. The output files of the jobs, in /var/opt/mssql/log, stay: T-SQL does
--    not delete them.
-- PachadataTraining itself is restored by the next module's 00-setup.sql.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The schedules, the commands as installed, the history.
IF EXISTS (SELECT * FROM dbo.sysschedules WHERE name = N'Integrity - every night at 1:00')
    EXEC dbo.sp_delete_schedule @schedule_name = N'Integrity - every night at 1:00', @force_delete = 1;
IF EXISTS (SELECT * FROM dbo.sysschedules WHERE name = N'Indexes - Sunday at 2:00')
    EXEC dbo.sp_delete_schedule @schedule_name = N'Indexes - Sunday at 2:00', @force_delete = 1;
-- The installation writes these commands with Windows line ends (CR LF): the same here, so
-- that the steps are again byte for byte as installed.
DECLARE @crlf nchar(2) = NCHAR(13) + NCHAR(10);
DECLARE @integrity nvarchar(max) = N'EXECUTE [dbo].[DatabaseIntegrityCheck]' + @crlf
    + N'@Databases = ''USER_DATABASES'',' + @crlf
    + N'@NoInformationalMessages = ''Y'',' + @crlf
    + N'@LogToTable = ''Y''';
DECLARE @index nvarchar(max) = N'EXECUTE [dbo].[IndexOptimize]' + @crlf
    + N'@Databases = ''USER_DATABASES'',' + @crlf
    + N'@LogToTable = ''Y''';
EXEC dbo.sp_update_jobstep
    @job_name = N'DatabaseIntegrityCheck - USER_DATABASES', @step_id = 1, @command = @integrity;
EXEC dbo.sp_update_jobstep
    @job_name = N'IndexOptimize - USER_DATABASES', @step_id = 1, @command = @index;
EXEC dbo.sp_purge_jobhistory @job_name = N'DatabaseIntegrityCheck - USER_DATABASES';
EXEC dbo.sp_purge_jobhistory @job_name = N'IndexOptimize - USER_DATABASES';
EXEC dbo.sp_purge_jobhistory @job_name = N'DatabaseIntegrityCheck - SYSTEM_DATABASES';
GO
-- 2. The database of 01b-damaged-page.sql.
IF DB_ID(N'IntegrityDemo') IS NOT NULL
BEGIN
    DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'IntegrityDemo');
    ALTER DATABASE IntegrityDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE IntegrityDemo;
END;
GO
-- 3. The backup files and the backup history.
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_11';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_11', N'bak', N'2100-01-01', 0;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_11', N'trn', N'2100-01-01', 0;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining';
GO
-- What is left: the jobs without schedule, no file in the module's folder.
SELECT j.name, sc.name AS schedule_name FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules AS sc ON sc.schedule_id = js.schedule_id
ORDER BY j.name;
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/module_11', 0, 1;
SELECT name FROM sys.databases WHERE database_id > 4;
GO
