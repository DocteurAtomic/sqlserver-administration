-- Module 7, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It gives the instance back as setup/install.sh left it, and takes a few seconds:
-- 1. Drops the database WebCatalog of 03b-contained-database.sql.
-- 2. Drops the logins PachadataWeb and PachadataMonitor, and the server role
--    EventSessionManager, emptied of its member by the drop of the login.
-- 3. Sets the option contained database authentication back to 0.
-- The users, roles, schema, procedure and certificate of the clips live in PachadataTraining,
-- which the next module's 00-setup.sql restores.
USE master;
SET NOCOUNT ON;
GO
-- 1. The contained database.
IF DB_ID(N'WebCatalog') IS NOT NULL
BEGIN
    ALTER DATABASE WebCatalog SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE WebCatalog;
END;
GO
-- 2. The logins and the server role of the module.
IF SUSER_ID(N'PachadataMonitor') IS NOT NULL DROP LOGIN PachadataMonitor;
IF SUSER_ID(N'PachadataWeb') IS NOT NULL DROP LOGIN PachadataWeb;
IF SUSER_ID(N'EventSessionManager') IS NOT NULL DROP SERVER ROLE EventSessionManager;
GO
-- 3. The instance option.
IF (SELECT value_in_use FROM sys.configurations
    WHERE name = N'contained database authentication') <> 0
BEGIN
    EXEC sys.sp_configure N'contained database authentication', 0;
    RECONFIGURE;
END;
GO
-- What is left: no login, server role or database of the module, the option at 0.
SELECT name FROM sys.server_principals
WHERE name IN (N'PachadataWeb', N'PachadataMonitor', N'EventSessionManager')
UNION ALL
SELECT name FROM sys.databases WHERE name = N'WebCatalog';
SELECT name, value_in_use FROM sys.configurations
WHERE name = N'contained database authentication';
GO
