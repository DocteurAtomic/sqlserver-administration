-- Clip 6.3: minimal logging, measured. Runs on the lab, in one session, after 04-export.sh
-- (the file /var/opt/mssql/exchange/invoice.csv). About ten seconds.
-- ci: skip (it needs the files of 04-export.sh)
-- 1. A staging database for the nightly loads, PachadataStaging, in SIMPLE (a new database
--    takes the recovery model of model, FULL on the lab).
-- 2. A procedure that loads invoice.csv into an empty table in one transaction, with or
--    without TABLOCK, and returns the log written by that transaction.
-- 3. The same load in SIMPLE, BULK_LOGGED and FULL, before and after a full backup. The
--    backup goes to /var/opt/mssql/backup/module_06; 99-cleanup.sql deletes it.
-- 4. The check of the request of the module.
USE master;
SET NOCOUNT ON;
GO
IF DB_ID(N'PachadataStaging') IS NOT NULL
BEGIN
    ALTER DATABASE PachadataStaging SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PachadataStaging;
END;
CREATE DATABASE PachadataStaging;
ALTER DATABASE PachadataStaging SET RECOVERY SIMPLE;
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_06';
GO
USE PachadataStaging;
GO
CREATE OR ALTER PROCEDURE dbo.measure_load
    @tablock bit,
    @clustered bit = 0   -- 1: an empty table with a clustered index instead of a heap
AS
BEGIN
    SET NOCOUNT ON;
    DROP TABLE IF EXISTS dbo.InvoiceStage;
    SELECT TOP (0) * INTO dbo.InvoiceStage FROM PachadataTraining.Enrollment.Invoice;
    IF @clustered = 1
        CREATE CLUSTERED INDEX cx_InvoiceStage ON dbo.InvoiceStage (InvoiceCode);
    CHECKPOINT;
    DECLARE @sql nvarchar(max) = N'BULK INSERT dbo.InvoiceStage
        FROM N''/var/opt/mssql/exchange/invoice.csv''
        WITH (FORMAT = ''CSV'', FIELDTERMINATOR = '';'''
        + CASE WHEN @tablock = 1 THEN N', TABLOCK' ELSE N'' END + N');';
    BEGIN TRANSACTION;
    EXEC (@sql);
    -- The log written by the current transaction, in this database.
    SELECT d.recovery_model_desc AS recovery_model, @tablock AS tablock,
           CASE @clustered WHEN 1 THEN N'clustered' ELSE N'heap' END AS target,
           (SELECT COUNT(*) FROM dbo.InvoiceStage) AS rows_loaded,
           t.database_transaction_log_record_count AS log_records,
           t.database_transaction_log_bytes_used / 1024 AS log_kb
    FROM sys.dm_tran_database_transactions AS t
    JOIN sys.databases AS d ON d.database_id = t.database_id
    WHERE t.database_id = DB_ID()
      AND t.transaction_id = CURRENT_TRANSACTION_ID();
    COMMIT;
END;
GO
-- 2. SIMPLE: without TABLOCK, one log record per row; with it, the allocations only.
EXEC dbo.measure_load @tablock = 0;
EXEC dbo.measure_load @tablock = 1;
EXEC dbo.measure_load @tablock = 1, @clustered = 1;
GO
-- 3. BULK_LOGGED: the same as SIMPLE.
ALTER DATABASE PachadataStaging SET RECOVERY BULK_LOGGED;
EXEC dbo.measure_load @tablock = 1;
GO
-- 4. FULL, before any full backup, then after one: TABLOCK no longer avoids the logging.
ALTER DATABASE PachadataStaging SET RECOVERY FULL;
EXEC dbo.measure_load @tablock = 1;
BACKUP DATABASE PachadataStaging
    TO DISK = N'/var/opt/mssql/backup/module_06/PachadataStaging_full.bak'
    WITH INIT, FORMAT;
EXEC dbo.measure_load @tablock = 0;
EXEC dbo.measure_load @tablock = 1;
GO
-- 5. The staging database goes back to SIMPLE, the mode of its nightly loads.
ALTER DATABASE PachadataStaging SET RECOVERY SIMPLE;
GO
-- 6. The request of the module: no snapshot left on the instance, the files of the
--    accounting team in the exchange folder.
SELECT name, source_database_id FROM sys.databases WHERE source_database_id IS NOT NULL;
SELECT file_or_directory_name, size_in_bytes
FROM sys.dm_os_enumerate_filesystem(N'/var/opt/mssql/exchange', N'*')
ORDER BY file_or_directory_name;
GO
