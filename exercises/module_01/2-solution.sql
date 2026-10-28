-- Module 1 exercise: solution. Runs on your lab, in one session, after 1-start.sql.
-- A few seconds. Reads the instance, raises the level of Exercise01_Legacy, then drops the
-- two databases of the exercise. The expected error of part 3 is caught by TRY ... CATCH.
USE master;
SET NOCOUNT ON;
GO
-------------------------------------------------------------------------------------------
-- Part 1. When did the instance start?
-------------------------------------------------------------------------------------------
-- Three clocks that agree within a few seconds: SQLOS, the services, and tempdb, which is
-- created again at every start.
SELECT i.sqlserver_start_time,
       DATEDIFF(MINUTE, i.sqlserver_start_time, SYSDATETIME()) AS minutes_up,
       (SELECT create_date FROM sys.databases WHERE name = N'tempdb') AS tempdb_created,
       (SELECT CONVERT(datetime2(0), last_startup_time)
        FROM sys.dm_server_services
        WHERE servicename LIKE N'MSSQLSERVER%' OR servicename LIKE N'SQL Server (%') AS service_started
FROM sys.dm_os_sys_info AS i;
GO
-------------------------------------------------------------------------------------------
-- Part 2. The services.
-------------------------------------------------------------------------------------------
-- On Linux, the view returns the engine and the Agent only, and no account for the engine.
-- On Windows it also returns the full-text launcher and the Launchpad when they are
-- installed, with their accounts. SQL Server Browser and SQL Writer are never in this view:
-- they are shared by all the instances of the machine, and are read in services.msc or in
-- SQL Server Configuration Manager.
SELECT servicename, startup_type_desc, status_desc, service_account, process_id
FROM sys.dm_server_services;
GO
-------------------------------------------------------------------------------------------
-- Part 3. The compatibility levels.
-------------------------------------------------------------------------------------------
-- 3a. The level of the instance is its major version times ten: 170 for SQL Server 2025.
--     The databases below it:
SELECT d.name, d.compatibility_level,
       CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) * 10 AS instance_level
FROM sys.databases AS d
WHERE d.compatibility_level < CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) * 10
ORDER BY d.name;

-- 3b. The new database took its recovery model from model: FULL, with no backup planned.
SELECT name, recovery_model_desc
FROM sys.databases
WHERE name IN (N'model', N'Exercise01_New');
GO
-- 3c. At level 130, the engine of 2025 does not know REGEXP_LIKE (error 195), although it
--     has it. The query is run as dynamic SQL so that the error can be caught.
USE Exercise01_Legacy;
BEGIN TRY
    EXEC (N'SELECT Code FROM dbo.CourseCode WHERE REGEXP_LIKE(Code, ''^[A-Z]{2,3}-[A-Z]{3}-[0-9]{2}$'');');
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO
-- 3d. At level 170, the same query returns the codes that follow the pattern.
ALTER DATABASE Exercise01_Legacy SET COMPATIBILITY_LEVEL = 170;
GO
USE Exercise01_Legacy;
SELECT Code FROM dbo.CourseCode
WHERE REGEXP_LIKE(Code, '^[A-Z]{2,3}-[A-Z]{3}-[0-9]{2}$')
ORDER BY Code;
GO
-------------------------------------------------------------------------------------------
-- Part 4. The maintenance branch and the edition family.
-------------------------------------------------------------------------------------------
-- For SQL Server 2025, the RTM is build 1000, the GDR applied to the RTM stay in 17.0.1xxx
-- and the CU start at 17.0.4006 (CU1): a build at 4000 or above is on the CU branch, with or
-- without a GDR on top. The thresholds of another version are read in its own builds page.
-- EngineEdition: 2 for Standard and Standard Developer, 3 for Enterprise, Enterprise
-- Developer and Evaluation, 4 for Express. A script tests this value, not the label.
USE master;
SELECT CONVERT(nvarchar(20), SERVERPROPERTY('ProductVersion')) AS build,
       CASE
           WHEN CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) <> 17
               THEN N'not SQL Server 2025: see the builds page of this version'
           WHEN CONVERT(int, PARSENAME(CONVERT(nvarchar(20), SERVERPROPERTY('ProductVersion')), 2)) < 4000
               THEN N'RTM or GDR branch'
           ELSE N'CU branch'
       END AS branch,
       CASE CONVERT(int, SERVERPROPERTY('EngineEdition'))
           WHEN 2 THEN N'Standard family'
           WHEN 3 THEN N'Enterprise family'
           WHEN 4 THEN N'Express'
           ELSE N'other: ' + CONVERT(nvarchar(10), SERVERPROPERTY('EngineEdition'))
       END AS edition_family;
-- The builds page of SQL Server 2025, read on 28 October 2026: 17.0.4065.4 is CU7, of
-- 16 July 2026; the latest CU is CU10, 17.0.5035.5, of 22 October 2026. The lab is three CU
-- behind.
-- https://learn.microsoft.com/troubleshoot/sql/releases/sqlserver-2025/build-versions
GO
-------------------------------------------------------------------------------------------
-- Part 5. The line of the instance in the register of the servers.
-------------------------------------------------------------------------------------------
SELECT @@SERVERNAME AS server_name,
       CONVERT(nvarchar(20), SERVERPROPERTY('ProductVersion')) AS build,
       CONVERT(nvarchar(10), SERVERPROPERTY('ProductUpdateLevel')) AS update_level,
       CONVERT(int, SERVERPROPERTY('EngineEdition')) AS engine_edition,
       CONVERT(datetime2(0), i.sqlserver_start_time) AS started_at,
       (SELECT COUNT(*) FROM sys.databases WHERE database_id > 4) AS user_databases,
       (SELECT COUNT(*) FROM sys.databases
        WHERE compatibility_level < CONVERT(int, SERVERPROPERTY('ProductMajorVersion')) * 10) AS below_instance_level
FROM sys.dm_os_sys_info AS i;
GO
-------------------------------------------------------------------------------------------
-- Cleanup: the two databases of the exercise.
-------------------------------------------------------------------------------------------
USE master;
ALTER DATABASE Exercise01_Legacy SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE Exercise01_Legacy;
ALTER DATABASE Exercise01_New SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE Exercise01_New;
GO
-------------------------------------------------------------------------------------------
-- Answers to the questions.
-------------------------------------------------------------------------------------------
-- tempdb: it is created again at every start of the instance, from model, so its
--   create_date is the time of the last start.
-- Services: on Windows, sys.dm_server_services also returns the full-text launcher and the
--   Launchpad when they are installed. SQL Server Browser is read in SQL Server
--   Configuration Manager or services.msc; it gives clients the port of the named instances
--   that listen on a dynamic port, and is useless otherwise.
-- REGEXP_LIKE: the compatibility level decides what syntax and optimizer behavior a database
--   gets. A database moved from 2016 keeps the behavior of 2016 until its level is raised,
--   which makes a migration reversible; the level is raised afterwards, with the Query Store
--   on.
-- FULL from model: the log keeps everything until a log backup, once a first full backup
--   exists. Without log backups, the log file grows until the disk is full.
-- EngineEdition: an integer that keeps its meaning across versions, while the Edition label
--   changes (Developer Edition became Enterprise Developer Edition in 2025).
-- SQL Server 2022: in its own builds page,
--   https://learn.microsoft.com/troubleshoot/sql/releases/sqlserver-2022/build-versions
