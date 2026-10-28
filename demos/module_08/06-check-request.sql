-- Clip 8.5: the request checked on the lab. Runs on the lab, in one session, after
-- 04-tde.sql. Reads only. Before 04-tde.sql, the first query returns no row.
USE master;
SET NOCOUNT ON;
GO
-- 1. Every TDE database, its certificate, and the date of the certificate's backup. A NULL
--    date is a database that cannot be restored anywhere else.
SELECT DB_NAME(k.database_id) AS database_name, k.encryption_state_desc,
       c.name AS certificate_name, c.expiry_date, c.pvt_key_last_backup_date
FROM sys.dm_database_encryption_keys AS k
JOIN sys.certificates AS c ON c.thumbprint = k.encryptor_thumbprint;
GO
-- 2. The contacts: no phone column in clear, an encrypted one, a hash for the search.
USE PachadataTraining;
GO
SELECT c.name AS column_name, t.name AS type_name, c.max_length
FROM sys.columns AS c
JOIN sys.types AS t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID(N'Contact.Contact') AND c.name LIKE N'Phone%';
-- 3. Who may decrypt: the permissions on the key and the certificate, besides dbo.
SELECT dp.class_desc, COALESCE(k.name, ce.name) AS securable, dp.permission_name,
       USER_NAME(dp.grantee_principal_id) AS grantee, dp.state_desc
FROM sys.database_permissions AS dp
LEFT JOIN sys.symmetric_keys AS k ON dp.class = 24 AND k.symmetric_key_id = dp.major_id
LEFT JOIN sys.certificates AS ce ON dp.class = 25 AND ce.certificate_id = dp.major_id
WHERE dp.class IN (24, 25);
GO
