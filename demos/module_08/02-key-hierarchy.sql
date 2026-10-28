-- Clip 8.2: the key hierarchy. Runs on the lab, in one session, after 00-setup.sql.
-- It writes two key files in /var/opt/mssql/backup/module_08, which a later run overwrites,
-- and creates the database master key of PachadataTraining, which the next module's
-- 00-setup.sql removes with the database. It takes a second.
USE master;
SET NOCOUNT ON;
GO
-- 1. The service master key: created by the instance at its first start, never by you.
SELECT name, algorithm_desc, key_length, create_date
FROM master.sys.symmetric_keys
WHERE name = N'##MS_ServiceMasterKey##';
SELECT sqlserver_start_time FROM sys.dm_os_sys_info;
GO
-- 2. Its backup, protected by its own password: the file goes out of the server, the
--    password into a password vault.
BACKUP SERVICE MASTER KEY
    TO FILE = N'/var/opt/mssql/backup/module_08/service_master_key.key'
    ENCRYPTION BY PASSWORD = N'Smk-Backup-2026!lab';
GO
-- 3. A database master key in PachadataTraining: encrypted by its password, and by the
--    service master key, which lets the instance open it without the password.
USE PachadataTraining;
GO
IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = N'##MS_DatabaseMasterKey##')
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'Dmk-PachadataTraining-2026!lab';
GO
SELECT name, is_master_key_encrypted_by_server
FROM sys.databases WHERE name = DB_NAME();
SELECT k.name, k.algorithm_desc, k.key_length, e.crypt_type, e.crypt_type_desc
FROM sys.symmetric_keys AS k
JOIN sys.key_encryptions AS e ON e.key_id = k.symmetric_key_id;
GO
-- 4. Its backup, with another password.
BACKUP MASTER KEY
    TO FILE = N'/var/opt/mssql/backup/module_08/PachadataTraining_master_key.key'
    ENCRYPTION BY PASSWORD = N'Dmk-Backup-2026!lab';
GO
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/module_08', 1, 1;
GO
