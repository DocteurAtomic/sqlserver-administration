-- Module 8, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It gives the instance back as setup/install.sh left it, and takes about five seconds:
-- 1. Restores PachadataTraining as delivered when it is still encrypted by TDE: a certificate
--    cannot be dropped while a database depends on it.
-- 2. Deletes the backup files (.bak) of /var/opt/mssql/backup/module_08, before the
--    certificate: xp_delete_file reads the header of each file, and the header of a TDE backup
--    needs the certificate. Then the backup history of PachadataTraining in msdb.
-- 3. Drops the TDE certificate, and the database master key of master when no other
--    certificate or asymmetric key of master uses it.
-- What T-SQL cannot undo: the key and certificate files stay in the folder, and tempdb stays
-- encrypted until the next restart of the instance. Both go with
--   docker exec sqladmcourse rm -rf /var/opt/mssql/backup/module_08
--   docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -Q "SHUTDOWN"
--   docker start sqladmcourse
USE master;
SET NOCOUNT ON;
GO
-- 1. The database, when TDE still encrypts it.
IF EXISTS (SELECT * FROM sys.dm_database_encryption_keys
           WHERE database_id = DB_ID(N'PachadataTraining'))
    EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
-- 2. The backup files, then the backup history.
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_08';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_08', N'bak', N'2100-01-01', 0;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataTraining';
GO
-- 3. The certificate, and the master key when nothing else needs it.
IF CERT_ID(N'TdeCert08') IS NOT NULL
    DROP CERTIFICATE TdeCert08;
IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
   AND NOT EXISTS (SELECT * FROM sys.certificates WHERE name NOT LIKE N'##%')
   AND NOT EXISTS (SELECT * FROM sys.asymmetric_keys WHERE name NOT LIKE N'##%')
    DROP MASTER KEY;
GO
-- What is left: no certificate, no TDE database; tempdb until the restart.
SELECT name FROM sys.certificates WHERE name NOT LIKE N'##%';
SELECT name FROM sys.symmetric_keys;
SELECT DB_NAME(database_id) AS database_name, encryption_state_desc
FROM sys.dm_database_encryption_keys;
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/module_08', 1, 1;
GO
