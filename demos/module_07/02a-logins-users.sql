-- Clip 7.2: the login of the website, and its user in PachadataTraining. Played for the video
-- on the throwaway container sqladm-07:
-- ci: skip (it creates a login, an instance object)
-- On your lab, run it part by part, with 02b-connect.sh between parts 2 and 3 and after
-- part 3; 99-cleanup.sql drops the login. The password is a lab password: in production, it
-- lives in the secret store of the application, never in a script.
USE master;
SET NOCOUNT ON;
GO
-- 1. A weak password. On Linux, without a custom policy, the instance asks for eight
--    characters from three of the four sets: error 33064.
BEGIN TRY
    CREATE LOGIN PachadataWeb WITH PASSWORD = N'pachadata';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
GO
-- 2. The login of the website: the policy checked, no expiration (an expired password would
--    stop the site), PachadataTraining as default database.
CREATE LOGIN PachadataWeb
    WITH PASSWORD = N'Web-Site-2026!lab',
         DEFAULT_DATABASE = PachadataTraining,
         CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
SELECT name, default_database_name, is_policy_checked, is_expiration_checked,
       LOGINPROPERTY(name, 'PasswordHashAlgorithm') AS hash_algorithm, sid
FROM sys.sql_logins
WHERE name = N'PachadataWeb';
GO
-- Now run 02b-connect.sh: the login cannot open its default database.

-- 3. The user, named differently from the login on purpose: the link is the SID.
USE PachadataTraining;
CREATE USER WebSite FOR LOGIN PachadataWeb WITH DEFAULT_SCHEMA = Course;
SELECT sp.name AS login_name, dp.name AS user_name, sp.sid AS login_sid, dp.sid AS user_sid
FROM sys.server_principals AS sp
JOIN sys.database_principals AS dp ON dp.sid = sp.sid
WHERE sp.name = N'PachadataWeb';
GO
-- Run 02b-connect.sh again: the login enters, and can read nothing yet.
