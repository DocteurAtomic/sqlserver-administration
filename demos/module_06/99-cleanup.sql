-- Module 6, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It gives the instance back as setup/install.sh left it, and takes a few seconds:
-- 1. Drops the snapshots left on PachadataTraining and PachadataTraining_Ex06, the staging
--    database PachadataStaging and the copy of the exercise, PachadataTraining_Ex06.
-- 2. Deletes the backup of 06-minimal-logging.sql and the backup history of PachadataStaging.
-- T-SQL deletes neither the exchange files nor folders: they go with
--   docker exec sqladmcourse rm -rf /var/opt/mssql/exchange /var/opt/mssql/backup/module_06
-- PachadataTraining itself is restored by the next module's 00-setup.sql.
USE master;
SET NOCOUNT ON;
GO
DECLARE @sql nvarchar(max) = N'';
SELECT @sql += N'DROP DATABASE ' + QUOTENAME(name) + N';'
FROM sys.databases
WHERE source_database_id IN (DB_ID(N'PachadataTraining'), DB_ID(N'PachadataTraining_Ex06'));
EXEC (@sql);
IF DB_ID(N'PachadataStaging') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataStaging SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataStaging;
END;
IF DB_ID(N'PachadataTraining_Ex06') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataTraining_Ex06 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataTraining_Ex06;
END;
GO
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_06';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_06', N'bak', N'2100-01-01', 0;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataStaging';
GO
-- What is left: no snapshot, no database of the module, no backup.
SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/module_06', 1, 1;
GO
