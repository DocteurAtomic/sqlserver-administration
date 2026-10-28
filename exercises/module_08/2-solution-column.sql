-- Module 8 exercise, solution of parts 1 and 2: the e-mail column encrypted, and its hash.
-- Runs on your lab, in one session, after 1-start.sql. It takes a few seconds.
-- The database stays for parts 3 and 4; 5-cleanup.sql drops it.
USE PachadataContacts_Ex08;
SET NOCOUNT ON;
GO
-- Part 1. The hierarchy: the database master key (keep its password: part 4 needs it), a
-- certificate protected by it, an AES_256 key protected by the certificate.
CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Dmk-Contacts-Ex08-2026!lab';
CREATE CERTIFICATE EmailCert
    WITH SUBJECT = N'Protection of the e-mail key', EXPIRY_DATE = '20291231';
CREATE SYMMETRIC KEY EmailKey
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE EmailCert;
GO
SELECT name, is_master_key_encrypted_by_server FROM sys.databases WHERE name = DB_NAME();
SELECT name, algorithm_desc, key_length FROM sys.symmetric_keys;
GO
-- The encrypted column. An encrypted value takes more room than the clear one: the size is
-- measured, then the column is declared with a margin.
ALTER TABLE Contact.Contact ADD EmailEncrypted varbinary(256) NULL;
GO
OPEN SYMMETRIC KEY EmailKey DECRYPTION BY CERTIFICATE EmailCert;
UPDATE Contact.Contact
SET EmailEncrypted = ENCRYPTBYKEY(KEY_GUID(N'EmailKey'), Email);
CLOSE SYMMETRIC KEY EmailKey;
GO
SELECT COUNT(EmailEncrypted) AS encrypted, MAX(DATALENGTH(Email)) AS max_clear_bytes,
       MAX(DATALENGTH(EmailEncrypted)) AS max_encrypted_bytes
FROM Contact.Contact;
GO
-- Part 2. What MailingTool sees: binary, and NULL through DECRYPTBYKEYAUTOCERT.
EXECUTE AS USER = N'MailingTool';
SELECT TOP (2) ContactId, EmailEncrypted,
       CONVERT(varchar(150), DECRYPTBYKEYAUTOCERT(CERT_ID(N'EmailCert'), NULL, EmailEncrypted)) AS decrypted
FROM Contact.Contact ORDER BY ContactId;
REVERT;
GO
-- A search by e-mail address: a hash of the address in lower case, with a secret prefix,
-- indexed. The same address typed with capitals finds the row.
ALTER TABLE Contact.Contact ADD EmailHash varbinary(32) NULL;
GO
UPDATE Contact.Contact
SET EmailHash = HASHBYTES('SHA2_256', CONCAT('Pacha#', LOWER(Email)))
WHERE Email IS NOT NULL;
CREATE INDEX ix_Contact_EmailHash ON Contact.Contact (EmailHash);
GO
SET STATISTICS IO ON;
SELECT ContactId, LastName
FROM Contact.Contact
WHERE EmailHash = HASHBYTES('SHA2_256', CONCAT('Pacha#', LOWER('J.Garcia@100dayloans.com')));
SET STATISTICS IO OFF;
GO
-- The clear column goes. The display needs the key, which dbo can open.
ALTER TABLE Contact.Contact DROP COLUMN Email;
GO
SELECT c.ContactId, c.LastName,
       CONVERT(varchar(150), DECRYPTBYKEYAUTOCERT(CERT_ID(N'EmailCert'), NULL, c.EmailEncrypted)) AS Email
FROM Contact.Contact AS c
WHERE c.EmailHash = HASHBYTES('SHA2_256', CONCAT('Pacha#', LOWER('J.Garcia@100dayloans.com')));
SELECT COL_LENGTH(N'Contact.Contact', N'Email') AS clear_column;
GO
