-- Clip 11.1, end: a damaged page, and what a repair costs. Runs on the lab, in one session.
-- It creates a small database, IntegrityDemo, with a copy of Enrollment.Invoice, damages one
-- data page of the copy on disk with DBCC WRITEPAGE (undocumented, test databases only),
-- checks the database, repairs it with REPAIR_ALLOW_DATA_LOSS, and counts what was lost.
-- CHECKDB runs WITH TABLERESULTS into a temporary table: its errors become rows, which also
-- lets this script run under sqlcmd -b. IntegrityDemo is dropped at the end.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'IntegrityDemo') IS NOT NULL
BEGIN
    ALTER DATABASE IntegrityDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE IntegrityDemo;
END;
CREATE DATABASE IntegrityDemo;
ALTER DATABASE IntegrityDemo SET RECOVERY SIMPLE;
GO
-- 1. The copy of the invoices, checked once while it is sound.
SELECT InvoiceCode, InvoiceDate, NetAmount, GrossAmount, CompanyId, ContactId
INTO IntegrityDemo.dbo.Invoice
FROM PachadataTraining.Enrollment.Invoice;
ALTER TABLE IntegrityDemo.dbo.Invoice ADD CONSTRAINT pk_Invoice PRIMARY KEY CLUSTERED (InvoiceCode);
DBCC CHECKDB (N'IntegrityDemo') WITH NO_INFOMSGS;
SELECT DATABASEPROPERTYEX(N'IntegrityDemo', 'LastGoodCheckDbTime') AS last_good_checkdb;
GO
-- 2. The data page that holds invoice FA2016-006000, damaged on disk: two bytes written past
--    the checksum. %%physloc%% (undocumented) gives the file, page and slot of a row.
DECLARE @page int = (
    SELECT l.page_id
    FROM IntegrityDemo.dbo.Invoice AS i
    CROSS APPLY sys.fn_PhysLocCracker(i.%%physloc%%) AS l
    WHERE i.InvoiceCode = 'FA2016-006000');
SELECT @page AS damaged_page;
ALTER DATABASE IntegrityDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DBCC WRITEPAGE (N'IntegrityDemo', 1, @page, 2000, 2, 0x4141, 1);
ALTER DATABASE IntegrityDemo SET MULTI_USER;
GO
-- 3. The check. Read the last lines first: how many errors, in which table, and the minimum
--    repair level.
DROP TABLE IF EXISTS #checkdb;
CREATE TABLE #checkdb (Error int, Level int, State int, MessageText nvarchar(2048),
    RepairLevel nvarchar(50), Status int, DbId int, DbFragId int, ObjectId int, IndexId int,
    PartitionId bigint, AllocUnitId bigint, RidDbId int, RidPruId int, [File] int, Page int,
    Slot int, RefDbId int, RefPruId int, RefFile int, RefPage int, RefSlot int, Allocation int);
INSERT INTO #checkdb
EXEC (N'DBCC CHECKDB (N''IntegrityDemo'') WITH NO_INFOMSGS, ALL_ERRORMSGS, TABLERESULTS');
SELECT Error, Level, RepairLevel, Page, LEFT(MessageText, 110) AS message FROM #checkdb;
-- A check that finds an error leaves the date where it was.
SELECT DATABASEPROPERTYEX(N'IntegrityDemo', 'LastGoodCheckDbTime') AS last_good_checkdb;
GO
-- 4. The repair: single-user mode, then REPAIR_ALLOW_DATA_LOSS. It deallocates the page and
--    rebuilds the clustered index without it.
SELECT SUM(rows) AS rows_before_repair
FROM IntegrityDemo.sys.partitions
WHERE object_id = OBJECT_ID(N'IntegrityDemo.dbo.Invoice') AND index_id = 1;
ALTER DATABASE IntegrityDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
TRUNCATE TABLE #checkdb;
INSERT INTO #checkdb
EXEC (N'DBCC CHECKDB (N''IntegrityDemo'', REPAIR_ALLOW_DATA_LOSS) WITH NO_INFOMSGS, ALL_ERRORMSGS, TABLERESULTS');
SELECT Error, Level, Page, LEFT(MessageText, 110) AS message FROM #checkdb WHERE Level = 10;
ALTER DATABASE IntegrityDemo SET MULTI_USER;
GO
-- 5. What it cost. Here the original table says which invoices are gone; in production,
--    nothing does.
SELECT COUNT(*) AS rows_after_repair FROM IntegrityDemo.dbo.Invoice;
SELECT COUNT(*) AS lost_invoices, MIN(i.InvoiceCode) AS first_lost, MAX(i.InvoiceCode) AS last_lost,
       SUM(i.NetAmount) AS lost_net_amount
FROM PachadataTraining.Enrollment.Invoice AS i
WHERE NOT EXISTS (SELECT * FROM IntegrityDemo.dbo.Invoice AS c WHERE c.InvoiceCode = i.InvoiceCode);
DBCC CHECKDB (N'IntegrityDemo') WITH NO_INFOMSGS;
SELECT DATABASEPROPERTYEX(N'IntegrityDemo', 'LastGoodCheckDbTime') AS last_good_checkdb;
GO
-- 6. Cleanup of the demonstration.
DELETE FROM msdb.dbo.suspect_pages WHERE database_id = DB_ID(N'IntegrityDemo');
ALTER DATABASE IntegrityDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE IntegrityDemo;
GO
