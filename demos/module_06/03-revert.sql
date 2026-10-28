-- Clip 6.1: back to the state of the snapshot. Runs on the lab, in one session, after
-- 01-create-snapshot.sql (and 02-two-snapshots.sql, which drops its second snapshot).
-- The revert needs the database to itself: no other query window, no Object Explorer node
-- open on PachadataTraining.
USE master;
SET NOCOUNT ON;
GO
-- 1. The files of the database before the revert: a log preallocated at 1,200 MB.
SELECT name, type_desc, size / 128 AS size_mb, growth / 128 AS growth_mb, is_percent_growth
FROM sys.master_files
WHERE database_id = DB_ID(N'PachadataTraining');
GO
-- 2. The revert: the pages copied in the sparse file are written back.
DECLARE @start datetime2 = SYSDATETIME();
RESTORE DATABASE PachadataTraining
    FROM DATABASE_SNAPSHOT = N'PachadataTraining_BeforeRelease';
SELECT DATEDIFF(millisecond, @start, SYSDATETIME()) AS revert_ms;
GO
-- 3. The release is gone, every change made since the snapshot with it.
SELECT COUNT(*) AS invoices, SUM(ReminderLevel) AS reminder_levels,
       SUM(CASE WHEN ReminderDate = '20261028' THEN 1 ELSE 0 END) AS reminded_today
FROM PachadataTraining.Enrollment.Invoice;
GO
-- 4. The revert rebuilt the log: 504 KB, growth of 10 %. The data file did not change.
SELECT name, type_desc, size * 8 AS size_kb, growth, is_percent_growth
FROM sys.master_files
WHERE database_id = DB_ID(N'PachadataTraining');
GO
-- 5. The log gets its size and growth back at once.
ALTER DATABASE PachadataTraining
    MODIFY FILE (NAME = PachadataTraining_log, SIZE = 1200MB, FILEGROWTH = 50MB);
SELECT name, type_desc, size / 128 AS size_mb, growth / 128 AS growth_mb, is_percent_growth
FROM sys.master_files
WHERE database_id = DB_ID(N'PachadataTraining');
GO
-- 6. The snapshot has done its job: dropped the same evening.
DROP DATABASE PachadataTraining_BeforeRelease;
SELECT name FROM sys.databases WHERE source_database_id IS NOT NULL;
GO
