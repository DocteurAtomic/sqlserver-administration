-- Module 6 exercise: solution of parts 1 and 2. Runs on your lab, in one session, after
-- 1-start.sql. About half a minute.
-- Part 1: a snapshot before a purge, its copy on write, the revert refused then done, and a
-- table recovered from a snapshot without a revert.
-- Part 2: minimal logging of INSERT ... SELECT and SELECT ... INTO, by recovery model.
-- The copy PachadataTraining_Ex06 stays for part 3 (3-solution-export.sh, then
-- 4-solution-load.sql, which drops it).
-- The revert needs the database to itself: close the other windows open on the copy.
USE master;
SET NOCOUNT ON;
GO
-------------------------------------------------------------------------------------------
-- Part 1. The snapshot.
-------------------------------------------------------------------------------------------
-- 1a. The snapshot before the purge: one sparse file for the one data file of the copy.
CREATE DATABASE PachadataTraining_Ex06_BeforePurge
    ON (NAME = PachadataTraining,
        FILENAME = N'/var/opt/mssql/data/PachadataTraining_Ex06_BeforePurge.ss')
    AS SNAPSHOT OF PachadataTraining_Ex06;
SELECT mf.name, mf.is_sparse, mf.size / 128 AS max_size_mb,
       vfs.size_on_disk_bytes / 1024 AS size_on_disk_kb,
       vfs.num_of_bytes_written / 1024 AS written_kb
FROM sys.master_files AS mf
JOIN sys.dm_io_virtual_file_stats(DB_ID(N'PachadataTraining_Ex06_BeforePurge'), NULL) AS vfs
  ON vfs.file_id = mf.file_id
WHERE mf.database_id = DB_ID(N'PachadataTraining_Ex06_BeforePurge');
GO
-- 1b. The purge of the e-learning team: the progress older than 2020.
DELETE FROM PachadataTraining_Ex06.Elearning.Progress WHERE LastActivity < '20200101';
SELECT (SELECT COUNT(*) FROM PachadataTraining_Ex06.Elearning.Progress) AS rows_database,
       (SELECT COUNT(*) FROM PachadataTraining_Ex06_BeforePurge.Elearning.Progress) AS rows_snapshot;
-- What the snapshot received, against the size of the table. On Linux, size_on_disk_bytes
-- stays at 0: read num_of_bytes_written, or du on the .ss file.
SELECT vfs.size_on_disk_bytes / 1024 AS size_on_disk_kb, vfs.num_of_writes,
       vfs.num_of_bytes_written / 1024 AS written_kb
FROM sys.dm_io_virtual_file_stats(DB_ID(N'PachadataTraining_Ex06_BeforePurge'), NULL) AS vfs;
SELECT SUM(used_page_count) * 8 AS progress_kb_before_purge
FROM PachadataTraining_Ex06_BeforePurge.sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'PachadataTraining_Ex06_BeforePurge.Elearning.Progress');
GO
-- 1c. A second snapshot: the revert is refused. SSMS shows error 3137 then 3013; TRY ...
--     CATCH only keeps the last one, 3013.
CREATE DATABASE PachadataTraining_Ex06_Second
    ON (NAME = PachadataTraining,
        FILENAME = N'/var/opt/mssql/data/PachadataTraining_Ex06_Second.ss')
    AS SNAPSHOT OF PachadataTraining_Ex06;
BEGIN TRY
    RESTORE DATABASE PachadataTraining_Ex06
        FROM DATABASE_SNAPSHOT = N'PachadataTraining_Ex06_BeforePurge';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
DROP DATABASE PachadataTraining_Ex06_Second;
GO
-- 1d. With one snapshot, the revert. The purge is gone, the log is rebuilt.
RESTORE DATABASE PachadataTraining_Ex06
    FROM DATABASE_SNAPSHOT = N'PachadataTraining_Ex06_BeforePurge';
SELECT COUNT(*) AS rows_after_revert FROM PachadataTraining_Ex06.Elearning.Progress;
SELECT name, type_desc, size * 8 AS size_kb, growth, is_percent_growth
FROM sys.master_files WHERE database_id = DB_ID(N'PachadataTraining_Ex06');
ALTER DATABASE PachadataTraining_Ex06
    MODIFY FILE (NAME = PachadataTraining_log, SIZE = 1200MB, FILEGROWTH = 50MB);
SELECT name, type_desc, size / 128 AS size_mb, growth / 128 AS growth_mb, is_percent_growth
FROM sys.master_files WHERE database_id = DB_ID(N'PachadataTraining_Ex06');
GO
-- 1e. A table dropped by mistake, recovered from a new snapshot, without a revert: the
--     change made after the snapshot must survive.
DROP DATABASE PachadataTraining_Ex06_BeforePurge;
CREATE DATABASE PachadataTraining_Ex06_Rescue
    ON (NAME = PachadataTraining,
        FILENAME = N'/var/opt/mssql/data/PachadataTraining_Ex06_Rescue.ss')
    AS SNAPSHOT OF PachadataTraining_Ex06;
GO
USE PachadataTraining_Ex06;
UPDATE Elearning.Progress SET TimeSpentSeconds = TimeSpentSeconds + 60
WHERE LastActivity >= '20260101';                 -- the change to keep
DROP TABLE Enrollment.Answer;                       -- the mistake
GO
SELECT * INTO Enrollment.Answer FROM PachadataTraining_Ex06_Rescue.Enrollment.Answer;
SELECT (SELECT COUNT(*) FROM Enrollment.Answer) AS answers_recovered,
       (SELECT COUNT(*) FROM PachadataTraining_Ex06_Rescue.Enrollment.Answer) AS answers_snapshot,
       (SELECT SUM(CAST(TimeSpentSeconds AS bigint)) FROM Elearning.Progress)
     - (SELECT SUM(CAST(TimeSpentSeconds AS bigint))
        FROM PachadataTraining_Ex06_Rescue.Elearning.Progress) AS seconds_kept;
-- SELECT ... INTO copies columns and rows only: the primary key, indexes, constraints and
-- permissions of the table are to be created again.
SELECT i.name AS index_name, i.type_desc
FROM PachadataTraining_Ex06_Rescue.sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'PachadataTraining_Ex06_Rescue.Enrollment.Answer')
UNION ALL
SELECT N'recovered: ' + ISNULL(i.name, N'(heap)'), i.type_desc
FROM sys.indexes AS i
WHERE i.object_id = OBJECT_ID(N'Enrollment.Answer');
GO
USE master;
DROP DATABASE PachadataTraining_Ex06_Rescue;
GO
-------------------------------------------------------------------------------------------
-- Part 2. Minimal logging of INSERT ... SELECT and SELECT ... INTO.
-------------------------------------------------------------------------------------------
USE PachadataTraining_Ex06;
GO
CREATE OR ALTER PROCEDURE dbo.measure_copy @tablock bit
AS
BEGIN
    SET NOCOUNT ON;
    DROP TABLE IF EXISTS dbo.ProgressCopy;
    SELECT TOP (0) * INTO dbo.ProgressCopy FROM Elearning.Progress;   -- an empty heap
    CHECKPOINT;
    BEGIN TRANSACTION;
    IF @tablock = 1
        INSERT INTO dbo.ProgressCopy WITH (TABLOCK) SELECT * FROM Elearning.Progress;
    ELSE
        INSERT INTO dbo.ProgressCopy SELECT * FROM Elearning.Progress;
    SELECT d.recovery_model_desc AS recovery_model,
           CASE @tablock WHEN 1 THEN N'INSERT WITH (TABLOCK)' ELSE N'INSERT' END AS statement,
           t.database_transaction_log_record_count AS log_records,
           t.database_transaction_log_bytes_used / 1024 AS log_kb
    FROM sys.dm_tran_database_transactions AS t
    JOIN sys.databases AS d ON d.database_id = t.database_id
    WHERE t.database_id = DB_ID() AND t.transaction_id = CURRENT_TRANSACTION_ID();
    COMMIT;
END;
GO
CREATE OR ALTER PROCEDURE dbo.measure_select_into
AS
BEGIN
    SET NOCOUNT ON;
    DROP TABLE IF EXISTS dbo.ProgressCopy;
    CHECKPOINT;
    BEGIN TRANSACTION;
    SELECT * INTO dbo.ProgressCopy FROM Elearning.Progress;
    SELECT d.recovery_model_desc AS recovery_model, N'SELECT INTO' AS statement,
           t.database_transaction_log_record_count AS log_records,
           t.database_transaction_log_bytes_used / 1024 AS log_kb
    FROM sys.dm_tran_database_transactions AS t
    JOIN sys.databases AS d ON d.database_id = t.database_id
    WHERE t.database_id = DB_ID() AND t.transaction_id = CURRENT_TRANSACTION_ID();
    COMMIT;
END;
GO
-- 2a. SIMPLE.
EXEC dbo.measure_copy @tablock = 0;
EXEC dbo.measure_copy @tablock = 1;
EXEC dbo.measure_select_into;
-- 2b. BULK_LOGGED.
ALTER DATABASE PachadataTraining_Ex06 SET RECOVERY BULK_LOGGED;
EXEC dbo.measure_copy @tablock = 1;
EXEC dbo.measure_select_into;
-- 2c. FULL, without any full backup: the log is truncated as in SIMPLE, yet the logging
--     follows the setting.
ALTER DATABASE PachadataTraining_Ex06 SET RECOVERY FULL;
EXEC dbo.measure_copy @tablock = 1;
EXEC dbo.measure_select_into;
GO
ALTER DATABASE PachadataTraining_Ex06 SET RECOVERY SIMPLE;
DROP TABLE dbo.ProgressCopy;
DROP PROCEDURE dbo.measure_copy;
DROP PROCEDURE dbo.measure_select_into;
GO
USE master;
GO
