-- Module 8, setup. Runs on the lab, in one session, before the first clip of the module.
-- It takes about five seconds.
-- 1. Restores PachadataTraining as delivered, at level 170: no key, no certificate, no
--    encryption.
-- 2. Removes what an earlier run of the module may have left on the instance: the TDE
--    certificate of master, and the database master key of master when nothing else uses it.
-- 3. Deletes the backup history of PachadataTraining, and creates the folder of the module's
--    key and backup files, /var/opt/mssql/backup/module_08. A certificate backup refuses to
--    overwrite its files (error 15240), and T-SQL deletes no key or certificate file: before
--    running the module again, empty the folder with
--      docker exec sqladmcourse rm -rf /var/opt/mssql/backup/module_08
-- A TDE database restored over leaves tempdb encrypted until the next restart of the instance.
-- The connection and the restore on another instance use a second container, created by
-- 01b-second-instance.sh. 99-cleanup.sql removes what the module adds to the instance.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
IF CERT_ID(N'TdeCert08') IS NOT NULL
    DROP CERTIFICATE TdeCert08;
IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
   AND NOT EXISTS (SELECT * FROM sys.certificates WHERE name NOT LIKE N'##%')
   AND NOT EXISTS (SELECT * FROM sys.asymmetric_keys WHERE name NOT LIKE N'##%')
    DROP MASTER KEY;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_08';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining';
GO
SELECT DB_NAME(database_id) AS database_name, encryption_state_desc
FROM sys.dm_database_encryption_keys;
SELECT name, is_encrypted FROM sys.databases WHERE name = N'PachadataTraining';
SELECT COUNT(*) AS keys_in_PachadataTraining FROM PachadataTraining.sys.symmetric_keys;
