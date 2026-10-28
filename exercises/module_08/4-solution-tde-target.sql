-- Module 8 exercise, solution of part 4: the restore on the second instance.
-- ci: skip (it runs on sqladm-08b, after "01b-second-instance.sh copy exercise_08")
-- In SSMS, connect to localhost,14434. Part 1 ends on an expected error. Part 4 cleans the
-- second instance up.
USE master;
SET NOCOUNT ON;
GO
-- 1. Without the certificate: error 33111, and its thumbprint.
RESTORE FILELISTONLY
    FROM DISK = N'/var/opt/mssql/backup/exercise_08/PachadataContacts_Ex08_tde.bak';
GO
-- 2. A master key in master of this instance, then the certificate from its files, and the
--    restore.
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Target-Master-Key-Ex08-2026!lab';
CREATE CERTIFICATE ExerciseTdeCert08
    FROM FILE = N'/var/opt/mssql/backup/exercise_08/ExerciseTdeCert08.cer'
    WITH PRIVATE KEY (FILE = N'/var/opt/mssql/backup/exercise_08/ExerciseTdeCert08.pvk',
                      DECRYPTION BY PASSWORD = N'Ex08-Cert-Backup-2026!lab');
GO
RESTORE DATABASE PachadataContacts_Ex08
    FROM DISK = N'/var/opt/mssql/backup/exercise_08/PachadataContacts_Ex08_tde.bak';
GO
-- 3. The addresses read NULL until the database master key is opened by its password and
--    encrypted by the service master key of this instance.
USE PachadataContacts_Ex08;
GO
SELECT COUNT(EmailEncrypted) AS encrypted,
       COUNT(CONVERT(varchar(150), DECRYPTBYKEYAUTOCERT(CERT_ID(N'EmailCert'), NULL, EmailEncrypted))) AS decrypted
FROM Contact.Contact;
OPEN MASTER KEY DECRYPTION BY PASSWORD = N'Dmk-Contacts-Ex08-2026!lab';
ALTER MASTER KEY ADD ENCRYPTION BY SERVICE MASTER KEY;
CLOSE MASTER KEY;
SELECT COUNT(CONVERT(varchar(150), DECRYPTBYKEYAUTOCERT(CERT_ID(N'EmailCert'), NULL, EmailEncrypted))) AS decrypted
FROM Contact.Contact;
SELECT c.ContactId, c.LastName,
       CONVERT(varchar(150), DECRYPTBYKEYAUTOCERT(CERT_ID(N'EmailCert'), NULL, c.EmailEncrypted)) AS Email
FROM Contact.Contact AS c
WHERE c.EmailHash = HASHBYTES('SHA2_256', CONCAT('Pacha#', LOWER('J.Garcia@100dayloans.com')));
GO
-- 4. Clean up the second instance.
USE master;
GO
ALTER DATABASE PachadataContacts_Ex08 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataContacts_Ex08;
DROP CERTIFICATE ExerciseTdeCert08;
IF NOT EXISTS (SELECT * FROM sys.certificates WHERE name NOT LIKE N'##%')
   AND NOT EXISTS (SELECT * FROM sys.asymmetric_keys WHERE name NOT LIKE N'##%')
    DROP MASTER KEY;
GO
SELECT DB_NAME(database_id) AS database_name, encryption_state_desc
FROM sys.dm_database_encryption_keys;
GO
