-- Clip 2.2: what the installation decided. Runs on the lab, in one session. Reads only.
USE master;
SET NOCOUNT ON;
GO
-- 1. The collation of the server and the authentication mode (0: mixed, 1: Windows only).
SELECT SERVERPROPERTY('Collation') AS server_collation,
       SERVERPROPERTY('IsIntegratedSecurityOnly') AS windows_only,
       SERVERPROPERTY('Edition') AS edition;
GO
-- 2. The members of sysadmin: who administers the instance.
SELECT m.name, m.type_desc, m.is_disabled
FROM sys.server_role_members AS rm
JOIN sys.server_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.server_principals AS m ON m.principal_id = rm.member_principal_id
WHERE r.name = N'sysadmin'
ORDER BY m.name;
GO
-- 3. tempdb: number, size and growth of its files.
SELECT name, type_desc, size * 8 / 1024 AS size_mb, growth * 8 / 1024 AS growth_mb
FROM sys.master_files
WHERE database_id = DB_ID(N'tempdb')
ORDER BY file_id;
GO
-- 4. MAXDOP and memory, as the installation left them.
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (N'max degree of parallelism', N'max server memory (MB)')
ORDER BY name;
GO
