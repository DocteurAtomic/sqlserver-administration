-- Clip 8.3: encrypt a column. Runs on the lab, in one session, after 00-setup.sql and
-- 02-key-hierarchy.sql (it creates the database master key of PachadataTraining if it is
-- missing). Everything it creates lives in PachadataTraining, which the next module's
-- 00-setup.sql restores. It takes about ten seconds.
-- The phone numbers of the contacts, encrypted by a symmetric key, readable by the support
-- team's account only with a permission on the certificate; a hash column for the search.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The keys: a certificate protected by the database master key, and an AES_256 key
--    protected by the certificate.
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Dmk-PachadataTraining-2026!lab';
CREATE CERTIFICATE ContactCert
    WITH SUBJECT = N'Protection of the contact keys', EXPIRY_DATE = '20291231';
CREATE SYMMETRIC KEY PhoneKey
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE ContactCert;
GO
SELECT name, algorithm_desc, key_length, key_guid FROM sys.symmetric_keys;
GO
-- 2. The encrypted column is a varbinary. The key opens for the session, then closes.
ALTER TABLE Contact.Contact ADD PhoneEncrypted varbinary(256) NULL;
GO
OPEN SYMMETRIC KEY PhoneKey DECRYPTION BY CERTIFICATE ContactCert;
UPDATE Contact.Contact
SET PhoneEncrypted = ENCRYPTBYKEY(KEY_GUID(N'PhoneKey'), Phone);
CLOSE SYMMETRIC KEY PhoneKey;
GO
SELECT COUNT(*) AS contacts, COUNT(Phone) AS phones, COUNT(PhoneEncrypted) AS encrypted,
       MAX(DATALENGTH(Phone)) AS phone_max_bytes,
       MIN(DATALENGTH(PhoneEncrypted)) AS encrypted_min_bytes,
       MAX(DATALENGTH(PhoneEncrypted)) AS encrypted_max_bytes
FROM Contact.Contact;
SELECT TOP (2) ContactId, Phone, PhoneEncrypted FROM Contact.Contact ORDER BY ContactId;
GO
-- 3. Key closed: DECRYPTBYKEY returns NULL, without an error.
SELECT TOP (2) ContactId, Phone,
       CONVERT(varchar(15), DECRYPTBYKEY(PhoneEncrypted)) AS decrypted
FROM Contact.Contact ORDER BY ContactId;
-- Key open: the numbers come back. Convert to the original type, varchar.
OPEN SYMMETRIC KEY PhoneKey DECRYPTION BY CERTIFICATE ContactCert;
SELECT key_name FROM sys.openkeys;
SELECT TOP (2) ContactId, Phone,
       CONVERT(varchar(15), DECRYPTBYKEY(PhoneEncrypted)) AS decrypted,
       CONVERT(nvarchar(15), DECRYPTBYKEY(PhoneEncrypted)) AS wrong_type
FROM Contact.Contact ORDER BY ContactId;
-- The same value encrypted twice: two different results.
SELECT CASE WHEN ENCRYPTBYKEY(KEY_GUID(N'PhoneKey'), '0102030405')
              = ENCRYPTBYKEY(KEY_GUID(N'PhoneKey'), '0102030405')
            THEN N'same' ELSE N'different' END AS two_encryptions;
CLOSE SYMMETRIC KEY PhoneKey;
GO
-- 4. The support team reads the table, without any right on the key or the certificate.
CREATE USER SupportAgent WITHOUT LOGIN;
GRANT SELECT ON Contact.Contact TO SupportAgent;
GO
EXECUTE AS USER = N'SupportAgent';
SELECT TOP (2) ContactId, PhoneEncrypted,
       CONVERT(varchar(15), DECRYPTBYKEYAUTOCERT(CERT_ID(N'ContactCert'), NULL, PhoneEncrypted)) AS decrypted
FROM Contact.Contact ORDER BY ContactId;
BEGIN TRY
    OPEN SYMMETRIC KEY PhoneKey DECRYPTION BY CERTIFICATE ContactCert;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
REVERT;
GO
-- It takes two permissions: VIEW DEFINITION on the key and CONTROL on the certificate.
-- Either one alone still returns NULL.
GRANT VIEW DEFINITION ON SYMMETRIC KEY::PhoneKey TO SupportAgent;
GRANT CONTROL ON CERTIFICATE::ContactCert TO SupportAgent;
GO
EXECUTE AS USER = N'SupportAgent';
SELECT TOP (2) ContactId,
       CONVERT(varchar(15), DECRYPTBYKEYAUTOCERT(CERT_ID(N'ContactCert'), NULL, PhoneEncrypted)) AS decrypted
FROM Contact.Contact ORDER BY ContactId;
REVERT;
GO
REVOKE CONTROL ON CERTIFICATE::ContactCert FROM SupportAgent;
REVOKE VIEW DEFINITION ON SYMMETRIC KEY::PhoneKey FROM SupportAgent;
GO
-- 5. A search by phone number cannot use the encrypted column: a hash column, indexed.
--    The prefix is a secret shared by every row, kept out of the database.
ALTER TABLE Contact.Contact ADD PhoneHash varbinary(32) NULL;
GO
UPDATE Contact.Contact
SET PhoneHash = HASHBYTES('SHA2_256', CONCAT('Pacha#', Phone))
WHERE Phone IS NOT NULL;
CREATE INDEX ix_Contact_PhoneHash ON Contact.Contact (PhoneHash);
GO
SET STATISTICS IO ON;
SELECT ContactId, LastName, FirstName
FROM Contact.Contact
WHERE PhoneHash = HASHBYTES('SHA2_256', CONCAT('Pacha#', '0435935688'));
SET STATISTICS IO OFF;
GO
-- 6. The clear column goes. The search goes through the hash, the display through the key.
DROP INDEX IF EXISTS ix_Contact_Phone ON Contact.Contact;
ALTER TABLE Contact.Contact DROP COLUMN Phone;
GO
SELECT c.ContactId, c.LastName,
       CONVERT(varchar(15), DECRYPTBYKEYAUTOCERT(CERT_ID(N'ContactCert'), NULL, c.PhoneEncrypted)) AS Phone
FROM Contact.Contact AS c
WHERE c.PhoneHash = HASHBYTES('SHA2_256', CONCAT('Pacha#', '0435935688'));
GO
