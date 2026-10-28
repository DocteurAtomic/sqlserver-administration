-- Clip 7.3: an orphaned user, found and repaired. Played for the video on the throwaway
-- container sqladm-07, after 02a-logins-users.sql:
-- ci: skip (it drops and recreates a login)
-- On your lab, run it part by part, with 02b-connect.sh after parts 1 and 3. A database
-- restored from another server gives the same orphan; restores are the subject of module 13.
USE master;
SET NOCOUNT ON;
GO
-- 1. The login recreated by hand, as on a new server: same name, same password, new SID.
--    The user WebSite stays in PachadataTraining with the old SID.
SELECT name, sid FROM sys.server_principals WHERE name = N'PachadataWeb';
DROP LOGIN PachadataWeb;
CREATE LOGIN PachadataWeb
    WITH PASSWORD = N'Web-Site-2026!lab',
         DEFAULT_DATABASE = PachadataTraining,
         CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
SELECT name, sid FROM sys.server_principals WHERE name = N'PachadataWeb';
GO
-- Run 02b-connect.sh: the login no longer enters its default database.

-- 2. Find the orphans: users mapped to a login (authentication INSTANCE) whose SID matches no
--    login. The filter leaves out users without login and the users of a contained database.
USE PachadataTraining;
SELECT dp.name AS user_name, dp.sid AS user_sid
FROM sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON sp.sid = dp.sid
WHERE sp.sid IS NULL
  AND dp.authentication_type_desc = N'INSTANCE';
GO
-- 3. Repair: the user takes the SID of the login, and keeps its roles and permissions.
ALTER USER WebSite WITH LOGIN = PachadataWeb;
SELECT name, sid, SUSER_SNAME(sid) AS login_name
FROM sys.database_principals
WHERE name = N'WebSite';
GO
-- Run 02b-connect.sh again: the login enters.

-- 4. Prevention: on the source server, the command that recreates the login with its SID
--    and the hash of its password. Run on the target, it leaves no orphan.
USE master;
SELECT CAST(N'CREATE LOGIN ' + QUOTENAME(name)
     + N' WITH PASSWORD = '
     + CONVERT(nvarchar(600), CAST(LOGINPROPERTY(name, 'PasswordHash') AS varbinary(256)), 1)
     + N' HASHED, SID = ' + CONVERT(nvarchar(100), sid, 1)
     + N', DEFAULT_DATABASE = ' + QUOTENAME(default_database_name)
     + N', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;' AS nvarchar(1000)) AS create_login
FROM sys.sql_logins
WHERE name = N'PachadataWeb';
GO
