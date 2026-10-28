-- Clip 8.5: restore the TDE database on another instance. Runs on the second instance,
-- sqladm-08b, never on the lab:
-- ci: skip (it needs the second instance of 01b-second-instance.sh, and the files copied
-- there by "01b-second-instance.sh copy" after 04-tde.sql)
-- In SSMS, connect to localhost,14434. Parts 1 and 2 end on expected errors. Part 6 drops
-- what the script created; tempdb stays encrypted until the restart of the instance.
USE master;
SET NOCOUNT ON;
GO
-- 0. The backup taken before TDE restores anywhere: here under another name, and the
--    contacts read in clear. The phone numbers stay NULL: the column key needs the
--    database master key, encrypted by the service master key of the source.
RESTORE DATABASE StolenCopy
    FROM DISK = N'/var/opt/mssql/backup/module_08/PachadataTraining_clear.bak'
    WITH MOVE N'PachadataTraining' TO N'/var/opt/mssql/data/StolenCopy.mdf',
         MOVE N'PachadataTraining_log' TO N'/var/opt/mssql/data/StolenCopy_log.ldf';
GO
USE StolenCopy;
SELECT TOP (2) ContactId, LastName, FirstName, Email, BirthDate,
       CONVERT(varchar(15), DECRYPTBYKEYAUTOCERT(CERT_ID(N'ContactCert'), NULL, PhoneEncrypted)) AS Phone
FROM Contact.Contact ORDER BY ContactId;
USE master;
DROP DATABASE StolenCopy;
GO
-- 1. Without the certificate, nothing reads, not even the header (error 33111). The
--    thumbprint in the message is the one of the certificate to provide.
RESTORE HEADERONLY
    FROM DISK = N'/var/opt/mssql/backup/module_08/PachadataTraining_tde.bak';
GO
-- 2. The restore fails the same way.
RESTORE DATABASE PachadataTraining
    FROM DISK = N'/var/opt/mssql/backup/module_08/PachadataTraining_tde.bak';
GO
-- 3. A database master key in master of this instance (nothing to do with the source's),
--    then the certificate recreated from its two files.
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Target-Master-Key-2026!lab';
CREATE CERTIFICATE TdeCert08
    FROM FILE = N'/var/opt/mssql/backup/module_08/TdeCert08.cer'
    WITH PRIVATE KEY (FILE = N'/var/opt/mssql/backup/module_08/TdeCert08.pvk',
                      DECRYPTION BY PASSWORD = N'Tde-Cert-Backup-2026!lab');
SELECT name, thumbprint FROM sys.certificates WHERE name = N'TdeCert08';
GO
-- 4. The restore goes through. The files land where they were on the source.
RESTORE DATABASE PachadataTraining
    FROM DISK = N'/var/opt/mssql/backup/module_08/PachadataTraining_tde.bak';
GO
SELECT DB_NAME(database_id) AS database_name, encryption_state_desc, encryptor_type
FROM sys.dm_database_encryption_keys;
GO
-- 5. The database reads, but the phone numbers are NULL, without an error: its database
--    master key is encrypted by the service master key of the source instance.
USE PachadataTraining;
GO
SELECT name, is_master_key_encrypted_by_server FROM sys.databases WHERE name = DB_NAME();
SELECT COUNT(*) AS contacts, COUNT(PhoneEncrypted) AS encrypted,
       COUNT(CONVERT(varchar(15), DECRYPTBYKEYAUTOCERT(CERT_ID(N'ContactCert'), NULL, PhoneEncrypted))) AS decrypted
FROM Contact.Contact;
GO
-- Opened by its password, then encrypted by the service master key of this instance.
OPEN MASTER KEY DECRYPTION BY PASSWORD = N'Dmk-PachadataTraining-2026!lab';
ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;
CLOSE MASTER KEY;
GO
SELECT name, is_master_key_encrypted_by_server FROM sys.databases WHERE name = DB_NAME();
SELECT COUNT(*) AS contacts,
       COUNT(CONVERT(varchar(15), DECRYPTBYKEYAUTOCERT(CERT_ID(N'ContactCert'), NULL, PhoneEncrypted))) AS decrypted
FROM Contact.Contact;
GO
-- 6. Clean up the second instance. In production, never drop a TDE certificate: old
--    backups and old portions of the log depend on it.
USE master;
GO
ALTER DATABASE PachadataTraining SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining;
DROP CERTIFICATE TdeCert08;
DROP MASTER KEY;
GO
SELECT DB_NAME(database_id) AS database_name, encryption_state_desc
FROM sys.dm_database_encryption_keys;
GO
