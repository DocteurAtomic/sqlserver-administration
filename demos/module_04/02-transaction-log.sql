-- Clip 4.2: the transaction log. Runs on the lab, in one session, after 01-create-database.sql.
-- It takes about fifteen seconds (part 2 waits ten).
-- The log of PachadataArchive was created at 8 MB, growing by 64 MB, and the load of the
-- previous clip ran as one transaction: the log had to hold all of it.
USE PachadataArchive;
SET NOCOUNT ON;
GO
-- 1. The size of the log file and the space used in it.
SELECT total_log_size_in_bytes / 1048576 AS log_file_mb,
       CAST(used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.dm_db_log_space_usage;
GO
-- 2. The growths of the log during the load, in the default trace (event 93, Log File
--    Auto Grow), since the database was created. The trace is written by buffers: read too
--    soon after the load, it can miss growths, hence the wait and the count computed from
--    the size of the file (8 MB, then steps of 64 MB).
WAITFOR DELAY '00:00:10';
DECLARE @trace nvarchar(260) = (SELECT path FROM sys.traces WHERE is_default = 1);
SELECT COUNT(*) AS log_growths,
       SUM(CAST(IntegerData AS bigint)) * 8 / 1024 AS mb_added,
       SUM(Duration) / 1000 AS total_ms,
       ((SELECT size / 128 FROM sys.database_files WHERE type_desc = N'LOG') - 8) / 64 AS growths_from_size
FROM sys.fn_trace_gettable(@trace, DEFAULT)
WHERE EventClass = 93
  AND DatabaseName = DB_NAME()
  AND StartTime >= (SELECT create_date FROM sys.databases WHERE database_id = DB_ID());
GO
-- 3. The virtual log files (VLF), grouped by size, in the order of the file.
SELECT CAST(vlf_size_mb AS decimal(9, 2)) AS vlf_size_mb, COUNT(*) AS vlf_count,
       CAST(MIN(vlf_begin_offset) / 1048576.0 AS decimal(9, 1)) AS first_offset_mb
FROM sys.dm_db_log_info(DB_ID())
GROUP BY vlf_size_mb
ORDER BY MIN(vlf_begin_offset);
SELECT COUNT(*) AS vlf_total FROM sys.dm_db_log_info(DB_ID());
GO
-- 4. Truncation. In SIMPLE, a checkpoint truncates the log: the space is reused, the file
--    keeps its size.
CHECKPOINT;
SELECT d.log_reuse_wait_desc, u.total_log_size_in_bytes / 1048576 AS log_file_mb,
       CAST(u.used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.databases AS d CROSS JOIN sys.dm_db_log_space_usage AS u
WHERE d.database_id = DB_ID();
GO
-- 5. A transaction left open (here in the same session, for the demo): the checkpoint
--    frees nothing written since it began, and the transaction reserves the log space
--    it would need to roll back.
BEGIN TRANSACTION;
UPDATE dbo.Activity SET DurationSeconds = DurationSeconds + 1 WHERE EventTime < '2019-01-01';
CHECKPOINT;
SELECT d.log_reuse_wait_desc,
       CAST(u.used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.databases AS d CROSS JOIN sys.dm_db_log_space_usage AS u
WHERE d.database_id = DB_ID();
SELECT s.session_id, t.database_transaction_begin_time,
       t.database_transaction_log_bytes_used / 1048576 AS log_used_mb,
       t.database_transaction_log_bytes_reserved / 1048576 AS log_reserved_mb
FROM sys.dm_tran_database_transactions AS t
JOIN sys.dm_tran_session_transactions AS s ON s.transaction_id = t.transaction_id
WHERE t.database_id = DB_ID();
GO
-- 6. The transaction ends (here, rolled back), and the next checkpoint truncates.
ROLLBACK;
CHECKPOINT;
SELECT d.log_reuse_wait_desc,
       CAST(u.used_log_space_in_bytes / 1048576.0 AS decimal(9, 1)) AS used_mb
FROM sys.databases AS d CROSS JOIN sys.dm_db_log_space_usage AS u
WHERE d.database_id = DB_ID();
GO
-- 7. The same reading for every database of the instance.
SELECT d.name, d.recovery_model_desc, d.log_reuse_wait_desc, l.vlf_count, l.log_mb, l.active_vlf
FROM sys.databases AS d
CROSS APPLY (SELECT COUNT(*) AS vlf_count,
                    CAST(SUM(i.vlf_size_mb) AS decimal(9, 1)) AS log_mb,
                    SUM(CAST(i.vlf_active AS int)) AS active_vlf
             FROM sys.dm_db_log_info(d.database_id) AS i) AS l
WHERE d.state_desc = N'ONLINE'
ORDER BY l.vlf_count DESC;
GO
