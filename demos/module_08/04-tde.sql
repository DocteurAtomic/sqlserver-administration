-- Clip 8.4: Transparent Data Encryption. Played for the video on the throwaway container
-- sqladm-08:
-- ci: skip (it creates a certificate in master, and leaves tempdb encrypted until the next
-- restart of the instance)
-- On your lab, run it in one session after 03-column-encryption.sql; it takes about a minute.
-- 99-cleanup.sql drops the certificate and the database master key of master. The certificate
-- files stay in /var/opt/mssql/backup/module_08.
USE master;
SET NOCOUNT ON;
GO
-- 0. Before TDE: the backup any thief can restore, kept for the comparison.
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_08/PachadataTraining_clear.bak'
    WITH COPY_ONLY, FORMAT, CHECKSUM, COMPRESSION (ALGORITHM = ZSTD);
GO
-- 1. In master: the database master key, when it is missing, and the TDE certificate.
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Master-Key-2026!lab';
CREATE CERTIFICATE TdeCert08
    WITH SUBJECT = N'TDE of PachadataTraining', EXPIRY_DATE = '20291231';
GO
SELECT name, expiry_date, pvt_key_last_backup_date, thumbprint
FROM sys.certificates WHERE name = N'TdeCert08';
GO
-- 2. Back it up, with its private key, before anything depends on it.
BACKUP CERTIFICATE TdeCert08
    TO FILE = N'/var/opt/mssql/backup/module_08/TdeCert08.cer'
    WITH PRIVATE KEY (FILE = N'/var/opt/mssql/backup/module_08/TdeCert08.pvk',
                      ENCRYPTION BY PASSWORD = N'Tde-Cert-Backup-2026!lab');
SELECT name, pvt_key_last_backup_date
FROM sys.certificates WHERE name = N'TdeCert08';
GO
-- 3. The database encryption key, protected by the certificate, then encryption on.
USE PachadataTraining;
GO
CREATE DATABASE ENCRYPTION KEY
    WITH ALGORITHM = AES_256
    ENCRYPTION BY SERVER CERTIFICATE TdeCert08;
ALTER DATABASE PachadataTraining SET ENCRYPTION ON;
GO
-- 4. ALTER DATABASE returns at once; the encryption scan runs in the background. One reading
--    every two seconds, until the database is encrypted.
DECLARE @t0 datetime2 = SYSDATETIME();
DECLARE @scan TABLE (seconds int, state nvarchar(60), scan_state nvarchar(60), percent_complete decimal(4, 1));
WHILE 1 = 1
BEGIN
    INSERT INTO @scan
    SELECT DATEDIFF(second, @t0, SYSDATETIME()), encryption_state_desc,
           encryption_scan_state_desc, percent_complete
    FROM sys.dm_database_encryption_keys
    WHERE database_id = DB_ID(N'PachadataTraining');
    IF EXISTS (SELECT * FROM sys.dm_database_encryption_keys
               WHERE database_id = DB_ID(N'PachadataTraining') AND encryption_state = 3)
       OR DATEDIFF(second, @t0, SYSDATETIME()) > 600
        BREAK;
    WAITFOR DELAY '00:00:02';
END;
SELECT * FROM @scan ORDER BY seconds;
GO
-- 5. The database, and tempdb with it, under a key the engine manages.
SELECT DB_NAME(database_id) AS database_name, encryption_state_desc, encryption_scan_state_desc,
       key_algorithm, key_length, encryptor_type
FROM sys.dm_database_encryption_keys;
SELECT name, is_encrypted FROM sys.databases WHERE name IN (N'tempdb', N'PachadataTraining');
GO
-- 6. A backup of the encrypted database: compressed all the same, since SQL Server
--    decrypts each page, compresses it, and encrypts it again.
USE master;
GO
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_08/PachadataTraining_tde.bak'
    WITH COPY_ONLY, FORMAT, CHECKSUM, COMPRESSION (ALGORITHM = ZSTD);
GO
SELECT m.physical_device_name,
       CAST(b.backup_size / 1048576.0 AS decimal(9, 1)) AS data_mb,
       CAST(b.compressed_backup_size / 1048576.0 AS decimal(9, 1)) AS file_mb
FROM msdb.dbo.backupset AS b
JOIN msdb.dbo.backupmediafamily AS m ON m.media_set_id = b.media_set_id
WHERE b.database_name = N'PachadataTraining' AND b.server_name = @@SERVERNAME
ORDER BY b.backup_set_id;
GO
