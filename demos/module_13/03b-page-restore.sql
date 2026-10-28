-- ci: skip (DBCC CHECKTABLE ends on expected errors, which stop sqlcmd -b)
-- Clip 13.3, end: restoring one page. Runs on the lab, in one session, alone.
-- It creates a small database, PageDemo, in FULL, with a copy of Contact.Contact, takes a
-- full backup, changes one contact in ten, damages one data page of the table on disk with
-- DBCC WRITEPAGE (undocumented, test databases only), then restores that page alone.
-- PageDemo is dropped at the end, with its rows in msdb.dbo.suspect_pages.
USE master;
SET NOCOUNT ON;
GO
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_13';
IF DB_ID(N'PageDemo') IS NOT NULL
BEGIN
    DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'PageDemo');
    ALTER DATABASE PageDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PageDemo;
END;
CREATE DATABASE PageDemo;
ALTER DATABASE PageDemo SET RECOVERY FULL;
GO
-- 1. The table, a full backup, then changes that only the log contains.
SELECT ContactId, FirstName, LastName, Email
INTO PageDemo.dbo.Contact
FROM PachadataTraining.Contact.Contact;
CREATE UNIQUE CLUSTERED INDEX cx_Contact ON PageDemo.dbo.Contact (ContactId);
BACKUP DATABASE PageDemo TO DISK = N'/var/opt/mssql/backup/module_13/PageDemo_full.bak'
    WITH INIT, FORMAT, CHECKSUM;
UPDATE PageDemo.dbo.Contact SET Email = UPPER(Email) WHERE ContactId % 10 = 0;
SELECT @@ROWCOUNT AS changed_after_full;
GO
-- 2. One data page of the table, damaged on disk.
DECLARE @page int = (
    SELECT MAX(allocated_page_page_id)
    FROM sys.dm_db_database_page_allocations(DB_ID(N'PageDemo'),
         OBJECT_ID(N'PageDemo.dbo.Contact'), 1, NULL, 'DETAILED')
    WHERE page_type_desc = 'DATA_PAGE');
SELECT @page AS damaged_page;
DROP TABLE IF EXISTS #damaged;
SELECT CONCAT(N'1:', @page) AS page INTO #damaged;
ALTER DATABASE PageDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DBCC WRITEPAGE (N'PageDemo', 1, @page, 2000, 2, 0x4141, 1);
ALTER DATABASE PageDemo SET MULTI_USER;
GO
-- A read of the page raises error 824, severity 24, which closes the connection: here,
-- DBCC CHECKTABLE reads the table instead, and reports the page with severity 16 errors
-- (8939, 8928, 8978, 8976). Both record the page in msdb.dbo.suspect_pages.
DBCC CHECKTABLE (N'PageDemo.dbo.Contact') WITH NO_INFOMSGS;
GO
WAITFOR DELAY '00:00:02';
SELECT file_id, page_id, event_type, error_count
FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'PageDemo');
GO
-- 3. The page alone, from the full backup, then a log backup taken now and restored: it
--    brings the page to the present.
--    In production, the list comes from suspect_pages, the pages separated by commas; here,
--    the page damaged in part 2.
DECLARE @pages nvarchar(100) = (SELECT page FROM #damaged);
SELECT @pages AS pages_to_restore;
RESTORE DATABASE PageDemo PAGE = @pages
    FROM DISK = N'/var/opt/mssql/backup/module_13/PageDemo_full.bak' WITH NORECOVERY;
BACKUP LOG PageDemo TO DISK = N'/var/opt/mssql/backup/module_13/PageDemo_log.trn'
    WITH INIT, FORMAT;
RESTORE LOG PageDemo FROM DISK = N'/var/opt/mssql/backup/module_13/PageDemo_log.trn'
    WITH RECOVERY;
GO
-- 4. The check: every row, the changes made after the full backup, CHECKDB, suspect_pages.
SELECT COUNT(*) AS contacts,
       SUM(CASE WHEN ContactId % 10 = 0
                 AND (Email IS NULL OR Email = UPPER(Email) COLLATE Latin1_General_CS_AS)
                THEN 1 ELSE 0 END) AS changed_after_full
FROM PageDemo.dbo.Contact;
DBCC CHECKDB (N'PageDemo') WITH NO_INFOMSGS;
SELECT file_id, page_id, event_type, error_count
FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'PageDemo');
GO
-- 5. Cleanup of the demonstration.
DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'PageDemo');
ALTER DATABASE PageDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PageDemo;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'PageDemo';
GO
