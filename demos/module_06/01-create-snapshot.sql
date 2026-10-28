-- Clip 6.1: a database snapshot before a release. Runs on the lab, in one session, after
-- 00-setup.sql.
-- The release of the web team raises the reminder level of the invoices due this month. Its
-- UPDATE lost its WHERE clause: it touches the 110,737 invoices.
USE master;
SET NOCOUNT ON;
GO
-- 1. The state before the release.
SELECT COUNT(*) AS invoices, SUM(ReminderLevel) AS reminder_levels,
       SUM(CASE WHEN ReminderDate = '20261028' THEN 1 ELSE 0 END) AS reminded_today
FROM PachadataTraining.Enrollment.Invoice;
GO
-- 2. The snapshot: one sparse file per data file of the source, named by its logical name.
--    No log file.
CREATE DATABASE PachadataTraining_BeforeRelease
    ON (NAME = PachadataTraining,
        FILENAME = N'/var/opt/mssql/data/PachadataTraining_BeforeRelease.ss')
    AS SNAPSHOT OF PachadataTraining;
GO
-- 3. The sparse file announces the size of the source file and holds almost nothing.
--    On Linux, size_on_disk_bytes stays at 0: num_of_bytes_written tells what was copied.
SELECT mf.name, mf.is_sparse, mf.size / 128 AS max_size_mb,
       vfs.size_on_disk_bytes / 1024 AS size_on_disk_kb,
       vfs.num_of_writes, vfs.num_of_bytes_written / 1024 AS written_kb
FROM sys.master_files AS mf
JOIN sys.dm_io_virtual_file_stats(DB_ID(N'PachadataTraining_BeforeRelease'), NULL) AS vfs
  ON vfs.file_id = mf.file_id
WHERE mf.database_id = DB_ID(N'PachadataTraining_BeforeRelease');
SELECT name, database_id, source_database_id, is_read_only
FROM sys.databases
WHERE database_id > 4
ORDER BY database_id;
GO
-- 4. The release, with its bug.
USE PachadataTraining;
UPDATE Enrollment.Invoice
SET ReminderLevel = ReminderLevel + 1, ReminderDate = '20261028';
-- the WHERE clause that went missing:
-- WHERE DueDate >= '20261001' AND DueDate < '20261028' AND ReminderLevel = 0;
GO
-- 5. The database has changed, the snapshot still shows the state before the release.
SELECT N'database' AS source, SUM(ReminderLevel) AS reminder_levels,
       SUM(CASE WHEN ReminderDate = '20261028' THEN 1 ELSE 0 END) AS reminded_today
FROM PachadataTraining.Enrollment.Invoice
UNION ALL
SELECT N'snapshot', SUM(ReminderLevel),
       SUM(CASE WHEN ReminderDate = '20261028' THEN 1 ELSE 0 END)
FROM PachadataTraining_BeforeRelease.Enrollment.Invoice;
GO
-- 6. Copy on write: the snapshot received the original of every page the UPDATE touched,
--    once. The table is about as big as what was written.
SELECT vfs.size_on_disk_bytes / 1024 AS size_on_disk_kb,
       vfs.num_of_writes, vfs.num_of_bytes_written / 1024 AS written_kb
FROM sys.dm_io_virtual_file_stats(DB_ID(N'PachadataTraining_BeforeRelease'), NULL) AS vfs;
SELECT SUM(used_page_count) AS invoice_pages, SUM(used_page_count) * 8 AS invoice_kb
FROM PachadataTraining.sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'PachadataTraining.Enrollment.Invoice');
GO
