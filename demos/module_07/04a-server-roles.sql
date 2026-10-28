-- Clip 7.4: the server roles, and a monitoring login built from the granular roles of
-- SQL Server 2022. Played for the video on the throwaway container sqladm-07, after
-- 02a-logins-users.sql:
-- ci: skip (it creates a login and a server role)
-- On your lab, run it in one go; 99-cleanup.sql drops the login and the role.
USE master;
SET NOCOUNT ON;
GO
-- 1. The fixed server roles: the nine historical ones, and the ten ##MS_...## of 2022.
SELECT CASE WHEN name LIKE N'##MS[_]%' THEN N'granular (2022)' ELSE N'historical' END AS family,
       COUNT(*) AS roles
FROM sys.server_principals
WHERE type = 'R' AND is_fixed_role = 1 OR name = N'public'
GROUP BY CASE WHEN name LIKE N'##MS[_]%' THEN N'granular (2022)' ELSE N'historical' END;
GO
-- 2. The login of the monitoring tool: the performance DMVs, entry into every database,
--    and nothing else.
CREATE LOGIN PachadataMonitor
    WITH PASSWORD = N'Monitor-2026!lab', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
ALTER SERVER ROLE [##MS_ServerPerformanceStateReader##] ADD MEMBER PachadataMonitor;
ALTER SERVER ROLE [##MS_DatabaseConnector##] ADD MEMBER PachadataMonitor;
GO
-- 3. What it sees, tried under its identity, then under the login of the website.
EXECUTE AS LOGIN = N'PachadataMonitor';
SELECT SUSER_SNAME() AS login_name,
       (SELECT COUNT(*) FROM sys.dm_exec_sessions) AS visible_sessions,
       HAS_PERMS_BY_NAME(NULL, NULL, N'VIEW SERVER STATE') AS view_server_state,
       HAS_PERMS_BY_NAME(NULL, NULL, N'VIEW SERVER PERFORMANCE STATE') AS view_performance_state;
USE PachadataTraining;
SELECT DB_NAME() AS current_database, USER_NAME() AS user_name,
       HAS_PERMS_BY_NAME(N'Course.Course', N'OBJECT', N'SELECT') AS can_read_courses;
USE master;
REVERT;
GO
EXECUTE AS LOGIN = N'PachadataWeb';
SELECT SUSER_SNAME() AS login_name,
       (SELECT COUNT(*) FROM sys.dm_exec_sessions) AS visible_sessions;
REVERT;
GO
-- 4. A user-defined server role, for a right that no fixed role gives alone: managing the
--    Extended Events sessions.
CREATE SERVER ROLE EventSessionManager AUTHORIZATION sa;
GRANT ALTER ANY EVENT SESSION TO EventSessionManager;
ALTER SERVER ROLE EventSessionManager ADD MEMBER PachadataMonitor;
SELECT r.name AS server_role, m.name AS member_name, r.is_fixed_role
FROM sys.server_role_members AS rm
JOIN sys.server_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.server_principals AS m ON m.principal_id = rm.member_principal_id
WHERE m.name IN (N'PachadataMonitor', N'PachadataWeb')
ORDER BY m.name, r.name;
GO
