-- Module 8 exercise, solution of part 3: TDE on the lab, the source instance.
-- ci: skip (TDE leaves tempdb encrypted until the next restart of the instance)
-- Runs on your lab, in one session, after 2-solution-column.sql. It takes a few seconds.
-- Then copy the folder to the second instance:
--   ./demos/module_08/01b-second-instance.sh create        (if it does not run yet)
--   ./demos/module_08/01b-second-instance.sh copy exercise_08
USE master;
SET NOCOUNT ON;
GO
-- 1. The database master key of master when it is missing, and the TDE certificate. Never
--    backed up yet: pvt_key_last_backup_date is NULL.
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Master-Key-Ex08-2026!lab';
CREATE CERTIFICATE ExerciseTdeCert08
    WITH SUBJECT = N'TDE of PachadataContacts_Ex08', EXPIRY_DATE = '20291231';
GO
SELECT name, expiry_date, pvt_key_last_backup_date, thumbprint
FROM sys.certificates WHERE name = N'ExerciseTdeCert08';
GO
-- 2. Its backup with the private key, before the database depends on it.
BACKUP CERTIFICATE ExerciseTdeCert08
    TO FILE = N'/var/opt/mssql/backup/exercise_08/ExerciseTdeCert08.cer'
    WITH PRIVATE KEY (FILE = N'/var/opt/mssql/backup/exercise_08/ExerciseTdeCert08.pvk',
                      ENCRYPTION BY PASSWORD = N'Ex08-Cert-Backup-2026!lab');
SELECT name, pvt_key_last_backup_date
FROM sys.certificates WHERE name = N'ExerciseTdeCert08';
GO
-- 3. The database encryption key and the encryption, followed until the scan completes.
USE PachadataContacts_Ex08;
GO
CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE ExerciseTdeCert08;
ALTER DATABASE PachadataContacts_Ex08 SET ENCRYPTION ON;
GO
DECLARE @i int = 0;
WHILE @i < 60 AND NOT EXISTS (SELECT * FROM sys.dm_database_encryption_keys
                              WHERE database_id = DB_ID(N'PachadataContacts_Ex08')
                                AND encryption_state = 3)
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @i += 1;
END;
SELECT DB_NAME(database_id) AS database_name, encryption_state_desc,
       encryption_scan_state_desc, encryptor_type
FROM sys.dm_database_encryption_keys;
GO
-- 4. The backup that leaves for the other instance.
USE master;
GO
BACKUP DATABASE PachadataContacts_Ex08
    TO DISK = N'/var/opt/mssql/backup/exercise_08/PachadataContacts_Ex08_tde.bak'
    WITH COPY_ONLY, FORMAT, CHECKSUM, COMPRESSION (ALGORITHM = ZSTD);
SELECT TOP (1) CAST(backup_size / 1048576.0 AS decimal(9, 1)) AS data_mb,
       CAST(compressed_backup_size / 1048576.0 AS decimal(9, 1)) AS file_mb
FROM msdb.dbo.backupset
WHERE database_name = N'PachadataContacts_Ex08' AND server_name = @@SERVERNAME
ORDER BY backup_set_id DESC;
GO
