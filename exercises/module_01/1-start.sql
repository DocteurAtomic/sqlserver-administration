-- Module 1 exercise: start. Runs on your lab, in one session, in a few seconds.
-- Creates two small databases that stand for what a DBA finds on an instance taken over
-- from another team:
--   Exercise01_Legacy, migrated from SQL Server 2016 and left at compatibility level 130;
--   Exercise01_New, created yesterday by a developer, with the options of model.
-- The exercise never writes in PachadataTraining. The solution drops both databases.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'Exercise01_Legacy') IS NOT NULL
BEGIN
    ALTER DATABASE Exercise01_Legacy SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Exercise01_Legacy;
END;
IF DB_ID(N'Exercise01_New') IS NOT NULL
BEGIN
    ALTER DATABASE Exercise01_New SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Exercise01_New;
END;
GO
CREATE DATABASE Exercise01_Legacy;
ALTER DATABASE Exercise01_Legacy SET RECOVERY SIMPLE;
ALTER DATABASE Exercise01_Legacy SET COMPATIBILITY_LEVEL = 130;
CREATE DATABASE Exercise01_New;
GO
-- The legacy database keeps the course codes of the catalog, to be checked by a pattern.
USE Exercise01_Legacy;
CREATE TABLE dbo.CourseCode (Code varchar(20) NOT NULL PRIMARY KEY);
INSERT INTO dbo.CourseCode (Code)
VALUES ('SQL-ADM-01'), ('SQL-OPT-02'), ('sql-adm-3'), ('PG-SQL-01'), ('SQLADM04');
GO
USE master;
SELECT name, compatibility_level, recovery_model_desc
FROM sys.databases
WHERE name LIKE N'Exercise01[_]%'
ORDER BY name;
GO
