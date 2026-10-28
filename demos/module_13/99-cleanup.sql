-- Module 13, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It gives the instance back as setup/install.sh left it, and takes a few seconds:
-- 1. Removes the Agent job "Module 13 - Clock" of 00-setup.sql, with its schedule and history.
-- 2. Drops the databases that a clip or the exercise may have left (copies, PageDemo), and
--    the table of tempdb written by 03a-human-error.sql.
-- 3. Deletes the backup files (.bak, .trn) of /var/opt/mssql/backup/module_13, and those of
--    the exercise in /var/opt/mssql/backup/exercise_13. T-SQL does not delete folders: the
--    empty folders go with
--      docker exec sqladmcourse rm -rf /var/opt/mssql/backup/module_13 /var/opt/mssql/backup/exercise_13
-- 4. Deletes the backup and restore history of the databases of the module in msdb.
-- PachadataTraining itself is restored by the next module's 00-setup.sql.
USE master;
SET NOCOUNT ON;
GO
-- 1. The clock job.
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'Module 13 - Clock')
    EXEC msdb.dbo.sp_delete_job @job_name = N'Module 13 - Clock', @delete_unused_schedule = 1;
GO
-- 2. The databases left by a clip or the exercise, and the table of tempdb.
DECLARE @name sysname, @q nvarchar(max);
DECLARE dbs CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN (N'PachadataTraining_Copy', N'PachadataTraining_Copy2', N'PachadataTraining_PIT',
                   N'PageDemo', N'PachadataTraining_Ex13', N'PachadataTraining_Ex13_Read',
                   N'PachadataTraining_Ex13_PIT');
OPEN dbs;
FETCH NEXT FROM dbs INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @q = N'DROP DATABASE ' + QUOTENAME(@name) + N';';
    IF DATABASEPROPERTYEX(@name, 'Status') = 'ONLINE'
        SET @q = N'ALTER DATABASE ' + QUOTENAME(@name) + N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE; ' + @q;
    EXEC (@q);
    FETCH NEXT FROM dbs INTO @name;
END;
CLOSE dbs;
DEALLOCATE dbs;
DELETE FROM msdb.dbo.suspect_pages WHERE database_id NOT IN (SELECT database_id FROM sys.databases);
DROP TABLE IF EXISTS tempdb.dbo.Module13Incident;
GO
-- 3. The backup files.
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_13';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_13', N'bak', N'2100-01-01', 0;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_13', N'trn', N'2100-01-01', 0;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/exercise_13';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/exercise_13', N'bak', N'2100-01-01', 0;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/exercise_13', N'trn', N'2100-01-01', 0;
GO
-- 4. The history.
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Copy';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Copy2';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_PIT';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PageDemo';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Ex13';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Ex13_Read';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining_Ex13_PIT';
GO
-- What is left: the empty folders, no backup, no job, no database of the module.
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/module_13', 0, 1;
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/exercise_13', 0, 1;
SELECT name FROM msdb.dbo.sysjobs WHERE name LIKE N'Module 13%';
SELECT name FROM sys.databases WHERE database_id > 4;
GO
