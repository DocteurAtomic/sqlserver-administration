-- Module 3 exercise: solution. Runs on your lab, in one session, after 1-start.sql. About ten
-- seconds. At the end it deletes what the exercise created: the database Exercise03_Default,
-- the backup files under /var/opt/mssql/backup/exercise_03 and their history in msdb, and the
-- copy PachadataTraining_Ex03. T-SQL deletes no folder: the empty folder goes with
--   docker exec sqladmcourse rm -r /var/opt/mssql/backup/exercise_03 The expected error of part 4 is caught by TRY ... CATCH.
USE master;
SET NOCOUNT ON;
GO
-------------------------------------------------------------------------------------------
-- Part 1. The system databases.
-------------------------------------------------------------------------------------------
-- The four visible ones. tempdb was created at the last start: its create_date says when.
SELECT database_id, name, recovery_model_desc, compatibility_level, collation_name, create_date
FROM sys.databases
WHERE database_id <= 4;

-- Resource follows the update level of the instance: same build, written by the CU.
SELECT SERVERPROPERTY('ResourceVersion')            AS resource_version,
       SERVERPROPERTY('ResourceLastUpdateDateTime') AS resource_updated,
       SERVERPROPERTY('ProductVersion')             AS product_version,
       SERVERPROPERTY('ProductUpdateLevel')         AS update_level;
GO
-------------------------------------------------------------------------------------------
-- Part 2. A database created with no option.
-------------------------------------------------------------------------------------------
-- It takes the recovery model, the sizes and the growth of model, and the collation of the
-- instance. In FULL, with no log backup, its log would grow until the disk is full.
CREATE DATABASE Exercise03_Default;
GO
SELECT d.name, d.recovery_model_desc, d.collation_name, d.is_query_store_on,
       mf.name AS logical_name, mf.size / 128 AS size_mb, mf.growth / 128 AS growth_mb
FROM sys.databases AS d
JOIN sys.master_files AS mf ON mf.database_id = d.database_id
WHERE d.name IN (N'model', N'Exercise03_Default')
ORDER BY d.database_id, mf.file_id;
GO
-------------------------------------------------------------------------------------------
-- Part 3. The last backup of each database.
-------------------------------------------------------------------------------------------
-- 3.1 Without a filter on the server: PachadataTraining looks backed up.
SELECT d.name AS database_name,
       MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS last_full,
       MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS last_log
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b ON b.database_name = d.name
WHERE d.name <> N'tempdb'
GROUP BY d.name
ORDER BY d.name;

-- 3.2 Where the row comes from: another server, written in msdb by a restore.
SELECT b.database_name, b.server_name, b.is_copy_only, b.backup_finish_date,
       rh.destination_database_name, rh.restore_date, @@SERVERNAME AS this_server
FROM msdb.dbo.backupset AS b
LEFT JOIN msdb.dbo.restorehistory AS rh ON rh.backup_set_id = b.backup_set_id
ORDER BY rh.restore_date;
GO
-- 3.3 Back up the three system databases that are backed up. tempdb and Resource are not.
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/exercise_03';
BACKUP DATABASE master TO DISK = N'/var/opt/mssql/backup/exercise_03/master.bak' WITH INIT, CHECKSUM;
BACKUP DATABASE model  TO DISK = N'/var/opt/mssql/backup/exercise_03/model.bak'  WITH INIT, CHECKSUM;
BACKUP DATABASE msdb   TO DISK = N'/var/opt/mssql/backup/exercise_03/msdb.bak'   WITH INIT, CHECKSUM;
GO
-- 3.4 The same query, filtered on this server: only the three system databases have a date.
SELECT d.name AS database_name,
       MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS last_full,
       MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS last_log
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b
       ON b.database_name = d.name
      AND b.server_name = @@SERVERNAME
WHERE d.name <> N'tempdb'
GROUP BY d.name
ORDER BY d.name;
GO
-------------------------------------------------------------------------------------------
-- Part 4. The collation of a temporary table.
-------------------------------------------------------------------------------------------
USE PachadataTraining_Ex03;
GO
-- 4.1 The conflict, on the names of the client companies.
CREATE TABLE #Customer (Name varchar(60) NOT NULL);
INSERT INTO #Customer (Name)
SELECT TOP (20) Name FROM Contact.Company ORDER BY CompanyId;

SELECT collation_name AS temp_column
FROM tempdb.sys.columns WHERE object_id = OBJECT_ID(N'tempdb..#Customer');
GO
BEGIN TRY
    EXEC (N'SELECT COUNT(*) AS companies
            FROM Contact.Company AS c
            JOIN #Customer AS t ON t.Name = c.Name;');
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO
DROP TABLE #Customer;
GO
-- 4.2 The fix in the declaration: COLLATE DATABASE_DEFAULT.
CREATE TABLE #Customer (Name varchar(60) COLLATE DATABASE_DEFAULT NOT NULL);
INSERT INTO #Customer (Name)
SELECT TOP (20) Name FROM Contact.Company ORDER BY CompanyId;

SELECT COUNT(*) AS companies
FROM Contact.Company AS c
JOIN #Customer AS t ON t.Name = c.Name;
DROP TABLE #Customer;
GO
-- 4.3 SELECT ... INTO copies the collation of the source column: no conflict.
SELECT TOP (20) Name INTO #Copy FROM Contact.Company ORDER BY CompanyId;
SELECT collation_name AS copied_column
FROM tempdb.sys.columns WHERE object_id = OBJECT_ID(N'tempdb..#Copy');
DROP TABLE #Copy;
GO
-- 4.4 COLLATE in the join: fixes one query, not the table. Put on the temporary column, as
--     here, the index on Contact.Company.Name stays usable.
CREATE TABLE #Customer (Name varchar(60) NOT NULL);
INSERT INTO #Customer (Name)
SELECT TOP (20) Name FROM Contact.Company ORDER BY CompanyId;

SELECT COUNT(*) AS companies
FROM Contact.Company AS c
JOIN #Customer AS t ON t.Name COLLATE DATABASE_DEFAULT = c.Name;
DROP TABLE #Customer;
GO
-- 4.5 To think about: two permanent tables of the same database, each column with its own
--     collation. The conflict does not need tempdb: the columns were declared that way.
BEGIN TRY
    EXEC (N'SELECT TOP (1) p.LastName
            FROM Contact.ProspectUS AS p
            JOIN Contact.ProspectUS_SQL_Latin1 AS l ON l.LastName = p.LastName;');
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
GO
-------------------------------------------------------------------------------------------
-- Part 5. The line of the server register: the inventory, with the last full backup.
-------------------------------------------------------------------------------------------
USE master;
GO
SELECT d.name AS database_name, d.recovery_model_desc, SUSER_SNAME(d.owner_sid) AS owner_name,
       d.collation_name,
       (SELECT MAX(b.backup_finish_date) FROM msdb.dbo.backupset AS b
        WHERE b.database_name = d.name AND b.type = 'D'
          AND b.server_name = @@SERVERNAME)                    AS last_full,
       CASE WHEN d.recovery_model_desc = N'FULL' AND d.database_id > 4
             AND NOT EXISTS (SELECT * FROM msdb.dbo.backupset AS b
                             WHERE b.database_name = d.name AND b.type = 'L'
                               AND b.server_name = @@SERVERNAME)
            THEN N'FULL, no log backup' ELSE N'' END              AS warning
FROM sys.databases AS d
WHERE d.name <> N'tempdb'
ORDER BY d.name;
GO
-------------------------------------------------------------------------------------------
-- Cleanup: the database, the backup files and their history, the copy.
-------------------------------------------------------------------------------------------
USE master;
GO
DROP DATABASE Exercise03_Default;
GO
EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/exercise_03', N'bak', N'2100-01-01', 0;
GO
-- The history of the three backups only, found by their file: the rest of msdb stays.
DECLARE @sets TABLE (backup_set_id int PRIMARY KEY, media_set_id int);
INSERT INTO @sets (backup_set_id, media_set_id)
SELECT bs.backup_set_id, bs.media_set_id
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE bmf.physical_device_name LIKE N'/var/opt/mssql/backup/exercise_03/%';
DELETE FROM msdb.dbo.restorefile      WHERE restore_history_id IN
    (SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE backup_set_id IN (SELECT backup_set_id FROM @sets));
DELETE FROM msdb.dbo.restorefilegroup WHERE restore_history_id IN
    (SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE backup_set_id IN (SELECT backup_set_id FROM @sets));
DELETE FROM msdb.dbo.restorehistory   WHERE backup_set_id IN (SELECT backup_set_id FROM @sets);
DELETE FROM msdb.dbo.backupfile       WHERE backup_set_id IN (SELECT backup_set_id FROM @sets);
DELETE FROM msdb.dbo.backupfilegroup  WHERE backup_set_id IN (SELECT backup_set_id FROM @sets);
DELETE FROM msdb.dbo.backupset        WHERE backup_set_id IN (SELECT backup_set_id FROM @sets);
DELETE FROM msdb.dbo.backupmediafamily WHERE media_set_id IN (SELECT media_set_id FROM @sets);
DELETE FROM msdb.dbo.backupmediaset    WHERE media_set_id IN (SELECT media_set_id FROM @sets);
GO
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'Exercise03_Default';
-- The restore of 1-start.sql: sp_delete_database_backuphistory does not delete it, since the
-- backup set has the name of the source database, PachadataTraining.
DELETE FROM msdb.dbo.restorefile WHERE restore_history_id IN
    (SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE destination_database_name = N'PachadataTraining_Ex03');
DELETE FROM msdb.dbo.restorefilegroup WHERE restore_history_id IN
    (SELECT restore_history_id FROM msdb.dbo.restorehistory WHERE destination_database_name = N'PachadataTraining_Ex03');
DELETE FROM msdb.dbo.restorehistory WHERE destination_database_name = N'PachadataTraining_Ex03';
ALTER DATABASE PachadataTraining_Ex03 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining_Ex03;
GO
-- What is left: no backup of this server, no database of the exercise.
SELECT COUNT(*) AS backups_of_this_server
FROM msdb.dbo.backupset WHERE server_name = @@SERVERNAME;
SELECT COUNT(*) AS restores_of_the_copy
FROM msdb.dbo.restorehistory WHERE destination_database_name = N'PachadataTraining_Ex03';
SELECT name FROM sys.databases WHERE name LIKE N'%Ex03' OR name LIKE N'Exercise03%';
EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup/exercise_03', 0, 1;
GO
