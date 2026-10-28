-- Module 7 exercise: solution. Runs on your lab, in one session, after 1-start.sql.
-- A few seconds. It creates a login, its user and a role, a backup and a restored copy,
-- then deletes them all at the end, PachadataElearning_Ex07 included.
-- The connections under the login of the platform are tried here by EXECUTE AS LOGIN; the
-- same tries by a real connection are given in comments, with the password passed by the
-- environment:
--   docker exec -it -e SQLCMDPASSWORD='Elearning-2026!lab' sqladmcourse \
--       /opt/mssql-tools18/bin/sqlcmd -S localhost -U PachadataElearning -C
USE master;
SET NOCOUNT ON;
GO
-------------------------------------------------------------------------------------------
-- Part 1. The login and its user.
-------------------------------------------------------------------------------------------
-- 1a. A password of one set of characters: error 33064 on Linux.
BEGIN TRY
    CREATE LOGIN PachadataElearning WITH PASSWORD = N'elearningplatform';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
GO
-- 1b. The login: policy checked, no expiration, the database of the platform by default.
CREATE LOGIN PachadataElearning
    WITH PASSWORD = N'Elearning-2026!lab',
         DEFAULT_DATABASE = PachadataElearning_Ex07,
         CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
SELECT name, default_database_name, is_policy_checked, is_expiration_checked,
       LOGINPROPERTY(name, 'PasswordHashAlgorithm') AS hash_algorithm
FROM sys.sql_logins WHERE name = N'PachadataElearning';
GO
-- 1c. Before the user exists, a real connection fails: "Cannot open user default database",
--     state 40 of error 18456 in the error log. Under EXECUTE AS LOGIN, the database refuses
--     the entry (error 916).
EXECUTE AS LOGIN = N'PachadataElearning';
BEGIN TRY
    EXEC (N'USE PachadataElearning_Ex07;');
END TRY
BEGIN CATCH
    SELECT N'before the user' AS moment, ERROR_NUMBER() AS error;
END CATCH;
REVERT;
GO
-- 1d. The user, linked to the login by its SID.
USE PachadataElearning_Ex07;
CREATE USER ElearningPlatform FOR LOGIN PachadataElearning;
SELECT sp.name AS login_name, dp.name AS user_name, sp.sid AS login_sid, dp.sid AS user_sid
FROM sys.server_principals AS sp
JOIN sys.database_principals AS dp ON dp.sid = sp.sid
WHERE sp.name = N'PachadataElearning';
GO
-------------------------------------------------------------------------------------------
-- Part 2. The role and its permissions.
-------------------------------------------------------------------------------------------
-- 2a. A role owned by dbo; the rights go to the role. Read the schema Elearning, read the
--     trainees without their birth date, record a progress only through the procedure.
CREATE ROLE ElearningApp AUTHORIZATION dbo;
ALTER ROLE ElearningApp ADD MEMBER ElearningPlatform;
GRANT SELECT ON SCHEMA::Elearning TO ElearningApp;
GRANT SELECT ON Contact.Trainee TO ElearningApp;
DENY SELECT ON Contact.Trainee (BirthDate) TO ElearningApp;
GRANT EXECUTE ON Elearning.RecordProgress TO ElearningApp;
GO
-- 2b. The effective permissions, under the identity of the user.
EXECUTE AS USER = N'ElearningPlatform';
SELECT USER_NAME() AS user_name, ORIGINAL_LOGIN() AS original_login,
       HAS_PERMS_BY_NAME(N'Elearning.Progress', N'OBJECT', N'SELECT') AS read_progress,
       HAS_PERMS_BY_NAME(N'Elearning.Progress', N'OBJECT', N'UPDATE') AS update_progress,
       HAS_PERMS_BY_NAME(N'Contact.Trainee', N'OBJECT', N'SELECT') AS read_trainee_table,
       HAS_PERMS_BY_NAME(N'Contact.Trainee', N'OBJECT', N'SELECT', N'BirthDate', N'COLUMN') AS read_birth_date;
SELECT subentity_name AS readable_column
FROM sys.fn_my_permissions(N'Contact.Trainee', N'OBJECT')
WHERE permission_name = N'SELECT' AND subentity_name <> N''
ORDER BY subentity_name;
SELECT TOP (2) ContactId, FirstName, LastName FROM Contact.Trainee ORDER BY ContactId;
BEGIN TRY
    SELECT TOP (1) * FROM Contact.Trainee;
END TRY
BEGIN CATCH
    SELECT N'SELECT *' AS statement_run, ERROR_NUMBER() AS error;
END CATCH;
-- 2c. The update: refused on the table, accepted through the procedure (same owner, dbo).
BEGIN TRY
    UPDATE Elearning.Progress SET ProgressPercent = 80
    WHERE EnrollmentId = 151236 AND ModuleId = 204;
END TRY
BEGIN CATCH
    SELECT N'UPDATE' AS statement_run, ERROR_NUMBER() AS error;
END CATCH;
EXEC Elearning.RecordProgress @EnrollmentId = 151236, @ModuleId = 204,
     @ProgressPercent = 80, @SecondsSpent = 300;
REVERT;
GO
-- 2d. The proof: the login is not sysadmin, holds no server role and no server permission
--     but CONNECT SQL, and its user is a member of ElearningApp only.
SELECT IS_SRVROLEMEMBER(N'sysadmin', N'PachadataElearning') AS is_sysadmin,
       (SELECT COUNT(*) FROM sys.server_role_members
        WHERE member_principal_id = SUSER_ID(N'PachadataElearning')) AS server_roles,
       (SELECT COUNT(*) FROM sys.server_permissions
        WHERE grantee_principal_id = SUSER_ID(N'PachadataElearning')
          AND permission_name <> N'CONNECT SQL') AS server_permissions,
       (SELECT STRING_AGG(USER_NAME(role_principal_id), N', ') FROM sys.database_role_members
        WHERE member_principal_id = USER_ID(N'ElearningPlatform')) AS database_roles;
GO
-------------------------------------------------------------------------------------------
-- Part 3. The orphan of the test server.
-------------------------------------------------------------------------------------------
-- 3a. The backup that goes to the test server, and the command that recreates the login
--     there with its SID and its password hash, generated on the source.
USE master;
BACKUP DATABASE PachadataElearning_Ex07
    TO DISK = N'/var/opt/mssql/backup/exercise_07/PachadataElearning_Ex07.bak'
    WITH COPY_ONLY, FORMAT, COMPRESSION, CHECKSUM;
DECLARE @create_login nvarchar(1000) = (
    SELECT N'CREATE LOGIN ' + QUOTENAME(name)
         + N' WITH PASSWORD = '
         + CONVERT(nvarchar(600), CAST(LOGINPROPERTY(name, 'PasswordHash') AS varbinary(256)), 1)
         + N' HASHED, SID = ' + CONVERT(nvarchar(100), sid, 1)
         + N', DEFAULT_DATABASE = ' + QUOTENAME(default_database_name)
         + N', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;'
    FROM sys.sql_logins WHERE name = N'PachadataElearning');
-- Kept in a table of tempdb for part 3e; in real life, in the migration script.
DROP TABLE IF EXISTS tempdb.dbo.ex07_create_login;
SELECT @create_login AS command INTO tempdb.dbo.ex07_create_login;
SELECT command FROM tempdb.dbo.ex07_create_login;
GO
-- 3b. On the test server, the login is created by hand: same name, same password, new SID.
DROP LOGIN PachadataElearning;
CREATE LOGIN PachadataElearning
    WITH PASSWORD = N'Elearning-2026!lab',
         DEFAULT_DATABASE = PachadataElearning_Ex07,
         CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
GO
-- 3c. The database arrives, restored under the name of the test copy.
RESTORE DATABASE PachadataElearning_Ex07_Test
    FROM DISK = N'/var/opt/mssql/backup/exercise_07/PachadataElearning_Ex07.bak'
    WITH MOVE N'PachadataElearning_Ex07' TO N'/var/opt/mssql/data/PachadataElearning_Ex07_Test.mdf',
         MOVE N'PachadataElearning_Ex07_log' TO N'/var/opt/mssql/data/PachadataElearning_Ex07_Test_log.ldf',
         CHECKSUM;
GO
-- 3d. The orphans, in both databases: the original kept the old SID too.
SELECT N'PachadataElearning_Ex07' AS database_name, dp.name AS user_name, dp.sid AS user_sid
FROM PachadataElearning_Ex07.sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON sp.sid = dp.sid
WHERE sp.sid IS NULL AND dp.authentication_type_desc = N'INSTANCE'
UNION ALL
SELECT N'PachadataElearning_Ex07_Test', dp.name, dp.sid
FROM PachadataElearning_Ex07_Test.sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON sp.sid = dp.sid
WHERE sp.sid IS NULL AND dp.authentication_type_desc = N'INSTANCE';
EXECUTE AS LOGIN = N'PachadataElearning';
BEGIN TRY
    EXEC (N'USE PachadataElearning_Ex07_Test;');
END TRY
BEGIN CATCH
    SELECT N'orphaned' AS moment, ERROR_NUMBER() AS error;
END CATCH;
REVERT;
GO
-- 3e. The repair without ALTER USER: the login made by hand gives way to the login
--     recreated with the SID of the source. Both databases find it again.
DROP LOGIN PachadataElearning;
DECLARE @create_login nvarchar(1000) = (SELECT command FROM tempdb.dbo.ex07_create_login);
EXEC (@create_login);
DROP TABLE tempdb.dbo.ex07_create_login;
SELECT N'PachadataElearning_Ex07' AS database_name, COUNT(*) AS orphans
FROM PachadataElearning_Ex07.sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON sp.sid = dp.sid
WHERE sp.sid IS NULL AND dp.authentication_type_desc = N'INSTANCE'
UNION ALL
SELECT N'PachadataElearning_Ex07_Test', COUNT(*)
FROM PachadataElearning_Ex07_Test.sys.database_principals AS dp
LEFT JOIN sys.server_principals AS sp ON sp.sid = dp.sid
WHERE sp.sid IS NULL AND dp.authentication_type_desc = N'INSTANCE';
GO
-- 3f. Under the login, the test copy opens, and the user kept its role.
EXECUTE AS LOGIN = N'PachadataElearning';
USE PachadataElearning_Ex07_Test;
SELECT DB_NAME() AS current_database, USER_NAME() AS user_name,
       IS_ROLEMEMBER(N'ElearningApp') AS in_role,
       (SELECT COUNT(*) FROM Elearning.Progress) AS progress_rows;
USE master;
REVERT;
GO
-------------------------------------------------------------------------------------------
-- Part 4. Cleanup: the two databases, the login, the backup file and its history.
-- T-SQL does not delete the folder: docker exec sqladmcourse rm -rf /var/opt/mssql/backup/exercise_07
-------------------------------------------------------------------------------------------
USE master;
ALTER DATABASE PachadataElearning_Ex07_Test SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataElearning_Ex07_Test;
ALTER DATABASE PachadataElearning_Ex07 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataElearning_Ex07;
DROP LOGIN PachadataElearning;
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/exercise_07', N'bak', N'2100-01-01', 0;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataElearning_Ex07';
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PachadataElearning_Ex07_Test';
GO
SELECT name FROM sys.server_principals WHERE name = N'PachadataElearning'
UNION ALL
SELECT name FROM sys.databases WHERE name LIKE N'PachadataElearning%';
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/exercise_07', 1, 1;
GO
