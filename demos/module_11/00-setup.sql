-- Module 11, setup. Runs on the lab, in one session, before the first clip of the module,
-- on a lab installed by setup/install.sh, which runs setup/install-ola.sh (Ola Hallengren's
-- scripts in the database DBA, with their Agent jobs, not scheduled).
-- It takes about ten seconds.
-- 1. Creates the folder of the module's backups, /var/opt/mssql/backup/module_11, and
--    deletes the backup files and the backup history that an earlier run left there.
-- 2. Restores PachadataTraining as delivered (recovery model SIMPLE), at level 170. Its
--    indexes are as the database was built: six clustered indexes of more than 1,000 pages
--    are fragmented at more than 97 %, which clip 11.2 measures.
-- 99-cleanup.sql removes what the module adds to the instance.
USE master;
SET NOCOUNT ON;
GO
IF OBJECT_ID(N'DBA.dbo.IndexOptimize') IS NULL
    RAISERROR (N'DBA.dbo.IndexOptimize is missing: run ./setup/install-ola.sh first.', 16, 1);
GO
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_11';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_11', N'bak', N'2100-01-01', 0;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_11', N'trn', N'2100-01-01', 0;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining';
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
SELECT name, recovery_model_desc, compatibility_level, is_auto_create_stats_on,
       is_auto_update_stats_on, page_verify_option_desc
FROM sys.databases
WHERE name IN (N'PachadataTraining', N'DBA');
