-- Module 8 exercise: cleanup of the lab. Runs on your lab, in one session, at the end.
-- Drops PachadataContacts_Ex08, deletes the backup file of the exercise (before the
-- certificate: xp_delete_file reads the header, which needs it) and its history, then drops
-- the TDE certificate of the exercise, and the database master key of master when nothing
-- else uses it. What T-SQL cannot undo: the certificate files, and tempdb encrypted until the
-- next restart of the instance. Then, in a terminal:
--   docker exec sqladmcourse rm -rf /var/opt/mssql/backup/exercise_08
--   docker exec -i sqladmcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -Q "SHUTDOWN"
--   docker start sqladmcourse
--   ./demos/module_08/01b-second-instance.sh remove
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'PachadataContacts_Ex08') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataContacts_Ex08 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataContacts_Ex08;
END;
GO
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/exercise_08';
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/exercise_08', N'bak', N'2100-01-01', 0;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataContacts_Ex08';
GO
IF CERT_ID(N'ExerciseTdeCert08') IS NOT NULL
    DROP CERTIFICATE ExerciseTdeCert08;
IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
   AND NOT EXISTS (SELECT * FROM sys.certificates WHERE name NOT LIKE N'##%')
   AND NOT EXISTS (SELECT * FROM sys.asymmetric_keys WHERE name NOT LIKE N'##%')
    DROP MASTER KEY;
GO
SELECT name FROM sys.databases WHERE name = N'PachadataContacts_Ex08';
SELECT name FROM sys.certificates WHERE name NOT LIKE N'##%';
SELECT DB_NAME(database_id) AS database_name, encryption_state_desc
FROM sys.dm_database_encryption_keys;
GO
