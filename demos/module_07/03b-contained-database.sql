-- Clip 7.3: a partially contained database, whose user carries its own password. Played for
-- the video on the throwaway container sqladm-07:
-- ci: skip (it changes the instance option contained database authentication)
-- On your lab, run it in one go, then 03c-contained-connect.sh; 99-cleanup.sql drops the
-- database WebCatalog and sets the option back to 0.
-- WebCatalog is the copy of the catalog that the website reads; it moves between the test
-- server and production, and its user must follow it without a login to recreate.
USE master;
SET NOCOUNT ON;
GO
-- 1. The instance option, off on an installed instance.
SELECT name, value_in_use FROM sys.configurations
WHERE name = N'contained database authentication';
EXEC sys.sp_configure N'contained database authentication', 1;
RECONFIGURE;
GO
-- 2. The database, with the English titles of the courses, then contained.
CREATE DATABASE WebCatalog;
GO
USE WebCatalog;
GO
CREATE SCHEMA Catalog AUTHORIZATION dbo;
GO
SELECT c.CourseId, c.Code, cl.Title, c.Duration
INTO Catalog.Course
FROM PachadataTraining.Course.Course AS c
JOIN PachadataTraining.Course.CourseLanguage AS cl
  ON cl.CourseId = c.CourseId AND cl.LanguageCode = 'EN';
ALTER TABLE Catalog.Course ADD CONSTRAINT PK_Course PRIMARY KEY (CourseId);
GO
USE master;
ALTER DATABASE WebCatalog SET CONTAINMENT = PARTIAL WITH NO_WAIT;
GO
-- 3. A contained user, with a password and no login. The password may not contain the name
--    of the user.
USE WebCatalog;
CREATE USER CatalogSync WITH PASSWORD = N'Web-Catalog-2026!lab', DEFAULT_SCHEMA = Catalog;
GRANT SELECT ON SCHEMA::Catalog TO CatalogSync;
SELECT name, type_desc, authentication_type_desc
FROM sys.database_principals WHERE name = N'CatalogSync';
SELECT COUNT(*) AS logins_named_CatalogSync
FROM sys.server_principals WHERE name = N'CatalogSync';
GO
-- 4. What still ties the database to the instance, and the collation of its catalog.
SELECT ue.class_desc,
       CASE ue.class_desc
            WHEN N'DATABASE_PRINCIPAL' THEN USER_NAME(ue.major_id)
            WHEN N'OBJECT_OR_COLUMN' THEN OBJECT_SCHEMA_NAME(ue.major_id) + N'.' + OBJECT_NAME(ue.major_id)
       END AS entity,
       ue.feature_name
FROM sys.dm_db_uncontained_entities AS ue;
SELECT name, containment_desc, collation_name, catalog_collation_type_desc
FROM sys.databases WHERE name = N'WebCatalog';
GO
