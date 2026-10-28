-- Module 12, setup. Runs on the lab, in one session, before the first clip of the module,
-- on a lab installed by setup/install.sh, which runs setup/install-ola.sh (Ola Hallengren's
-- scripts in the database DBA, and /var/opt/mssql/backup writable by SQL Server).
-- It takes about ten seconds.
-- 1. Creates the folder of the module's backups, /var/opt/mssql/backup/module_12, and
--    deletes the backup files and the backup history that an earlier run left there.
-- 2. Restores PachadataTraining as delivered (recovery model SIMPLE), at level 170.
-- 99-cleanup.sql removes what the module adds to the instance.
USE master;
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'DBA.dbo.DatabaseBackup') IS NULL
    RAISERROR (N'DBA.dbo.DatabaseBackup is missing: run ./setup/install-ola.sh first.', 16, 1);
GO
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_12';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_12', N'bak', N'2100-01-01', 1;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_12', N'trn', N'2100-01-01', 1;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining';
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, recovery_model_desc, compatibility_level
FROM sys.databases
WHERE name IN (N'PachadataTraining', N'DBA');
