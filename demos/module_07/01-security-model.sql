-- Clip 7.1: the security model, read on the instance and in the database. Runs on the lab,
-- in one session, after 00-setup.sql. It only reads, and takes a second.
-- 1. The authentication mode of the instance.
-- 2. The principals of the instance: logins and server roles, stored in master.
-- 3. The principals of PachadataTraining: the four built-in users, and guest without CONNECT.
-- 4. The securables, by the classes of permissions that the engine knows.
USE master;
SET NOCOUNT ON;
GO
-- 1. 0: Windows and SQL Server authentication (mixed mode). 1: Windows only.
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS windows_only;
GO
-- 2. The server principals, by type.
SELECT type_desc, COUNT(*) AS principals
FROM sys.server_principals
GROUP BY type_desc
ORDER BY principals DESC;

SELECT name, type_desc, is_disabled
FROM sys.server_principals
WHERE type IN ('S', 'U', 'G') AND name NOT LIKE N'##%'
ORDER BY name;
GO
-- 3. The database principals of PachadataTraining, and the right to enter it.
USE PachadataTraining;
SELECT dp.name, dp.type_desc, dp.authentication_type_desc,
       CASE WHEN EXISTS (SELECT * FROM sys.database_permissions AS pe
                         WHERE pe.grantee_principal_id = dp.principal_id
                           AND pe.class = 0 AND pe.permission_name = N'CONNECT'
                           AND pe.state IN ('G', 'W'))
            THEN 1 ELSE 0 END AS can_connect
FROM sys.database_principals AS dp
WHERE dp.type IN ('S', 'U', 'G')
ORDER BY dp.principal_id;
GO
-- 4. The permissions the engine knows, by class of securable.
SELECT class_desc, COUNT(*) AS permissions
FROM sys.fn_builtin_permissions(DEFAULT)
WHERE class_desc IN (N'SERVER', N'DATABASE', N'SCHEMA', N'OBJECT', N'LOGIN', N'USER', N'ROLE')
GROUP BY class_desc
ORDER BY permissions DESC;
GO
