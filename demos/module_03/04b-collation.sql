-- Clip 3.4: the collation conflict with tempdb. Runs on the lab, in one session, after
-- 00-setup.sql. Reads Contact.Contact and works in temporary tables only.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. Three collations: the instance, tempdb (which takes the instance's), the database and
--    one of its columns.
SELECT SERVERPROPERTY('Collation')                         AS instance,
       DATABASEPROPERTYEX(N'tempdb', 'Collation')          AS tempdb,
       DATABASEPROPERTYEX(N'PachadataTraining', 'Collation') AS database_collation,
       (SELECT collation_name FROM sys.columns
        WHERE object_id = OBJECT_ID(N'Contact.Contact') AND name = N'LastName') AS last_name;
GO
-- 2. The conflict. A temporary table declared with no collation takes tempdb's.
CREATE TABLE #Search (LastName varchar(50) NOT NULL);
INSERT INTO #Search (LastName) VALUES ('Martin'), ('Bernard');

SELECT collation_name AS temp_column
FROM tempdb.sys.columns
WHERE object_id = OBJECT_ID(N'tempdb..#Search');
GO
-- Error 468 is raised at compile time: TRY ... CATCH in the same batch would not see it. The
-- query runs through EXEC, compiled apart, so the script goes on and shows the error.
BEGIN TRY
    EXEC (N'SELECT COUNT(*) AS contacts
            FROM Contact.Contact AS c
            JOIN #Search AS s ON s.LastName = c.LastName;');
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO
DROP TABLE #Search;
GO
-- 3. The fix in the code: the column takes the collation of the current database, whatever
--    the instance's.
CREATE TABLE #Search (LastName varchar(50) COLLATE DATABASE_DEFAULT NOT NULL);
INSERT INTO #Search (LastName) VALUES ('Martin'), ('Bernard');

SELECT collation_name AS temp_column
FROM tempdb.sys.columns
WHERE object_id = OBJECT_ID(N'tempdb..#Search');

SELECT COUNT(*) AS contacts
FROM Contact.Contact AS c
JOIN #Search AS s ON s.LastName = c.LastName;

DROP TABLE #Search;
GO
