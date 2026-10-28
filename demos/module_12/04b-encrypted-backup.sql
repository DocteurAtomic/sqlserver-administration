-- Clip 12.4: an encrypted backup. Played for the video on the throwaway container sqladm-12:
-- ci: skip (it creates a database master key and a certificate in master; part 5 ends on an
-- expected error)
-- On your lab, run it part by part; 99-cleanup.sql drops the certificate, and the master
-- key when nothing else uses it. The certificate files stay in /var/opt/mssql/backup/module_12.
USE master;
SET NOCOUNT ON;
GO
-- 1. The database master key of master protects the private key of the certificate.
--    Create it only when it is missing. No comma in SUBJECT: it separates the parts of an
--    X.500 name, and CREATE CERTIFICATE fails with error 15297.
SELECT name, create_date FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##';
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Master-Key-2026!lab';
CREATE CERTIFICATE BackupCert12
    WITH SUBJECT = N'Backup encryption of module 12', EXPIRY_DATE = '20291231';
GO
-- 2. An encrypted backup at once, before the certificate is backed up: it succeeds, with a
--    warning.
BACKUP DATABASE PachadataTraining
    TO DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_encrypted.bak'
    WITH COPY_ONLY, FORMAT, CHECKSUM, COMPRESSION (ALGORITHM = ZSTD),
         ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = BackupCert12);
GO
-- 3. Back up the certificate and its private key, then check the date of that backup.
BACKUP CERTIFICATE BackupCert12
    TO FILE = N'/var/opt/mssql/backup/module_12/BackupCert12.cer'
    WITH PRIVATE KEY (FILE = N'/var/opt/mssql/backup/module_12/BackupCert12.pvk',
                      ENCRYPTION BY PASSWORD = N'Cert-Backup-2026!lab');
SELECT name, expiry_date, pvt_key_last_backup_date, thumbprint
FROM sys.certificates WHERE name = N'BackupCert12';
GO
-- 4. What msdb recorded: the algorithm, the certificate, the size.
SELECT TOP (1) key_algorithm, encryptor_type, compression_algorithm,
       CAST(compressed_backup_size / 1048576.0 AS decimal(9, 1)) AS file_mb
FROM msdb.dbo.backupset
WHERE database_name = N'PachadataTraining' AND server_name = @@SERVERNAME
ORDER BY backup_set_id DESC;
GO
-- 5. Without the certificate, even the header cannot be read (error 33111).
DROP CERTIFICATE BackupCert12;
GO
RESTORE HEADERONLY
    FROM DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_encrypted.bak';
GO
-- 6. The certificate recreated from its two files: same thumbprint, the backup reads again.
CREATE CERTIFICATE BackupCert12
    FROM FILE = N'/var/opt/mssql/backup/module_12/BackupCert12.cer'
    WITH PRIVATE KEY (FILE = N'/var/opt/mssql/backup/module_12/BackupCert12.pvk',
                      DECRYPTION BY PASSWORD = N'Cert-Backup-2026!lab');
SELECT name, thumbprint FROM sys.certificates WHERE name = N'BackupCert12';
RESTORE VERIFYONLY
    FROM DISK = N'/var/opt/mssql/backup/module_12/PachadataTraining_encrypted.bak'
    WITH CHECKSUM;
GO
