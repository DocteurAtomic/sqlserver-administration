-- ci: skip (DatabaseIntegrityCheck ends on the expected CHECKDB errors, which stop sqlcmd -b)
-- Module 11 exercise, solution of part 1: checking the accounting database with
-- DatabaseIntegrityCheck, reading the failure, then repairing the copy and counting the loss.
-- Runs on your lab, in one session, after 1-start.sql. A few seconds.
USE DBA;
SET NOCOUNT ON;
GO
-- 1. The check. The procedure prints the CHECKDB errors (8939, 8928, 8978, 8976), then
--    "Outcome: Failed".
EXECUTE dbo.DatabaseIntegrityCheck
    @Databases = N'PachadataTraining_Ex11',
    @CheckCommands = N'CHECKDB',
    @NoInformationalMessages = N'Y',
    @LogToTable = N'Y';
GO
-- 2. What CommandLog kept: the command, the duration, the number of the last error. The text
--    of the CHECKDB errors is not there (ErrorMessage is NULL): it is in the output of the
--    procedure, or in the output file of a job.
SELECT ID, DatabaseName, CommandType, Command, DATEDIFF(millisecond, StartTime, EndTime) AS duration_ms,
       ErrorNumber, ErrorMessage
FROM dbo.CommandLog
WHERE DatabaseName = N'PachadataTraining_Ex11' AND CommandType = N'DBCC_CHECKDB'
ORDER BY ID DESC;
-- The date of the last check without error has not moved: it is still the date written in
-- the delivered backup.
SELECT DATABASEPROPERTYEX(N'PachadataTraining_Ex11', 'LastGoodCheckDbTime') AS last_good_checkdb;
GO
-- 3. Before the repair, the rows of the archive according to the metadata: COUNT(*) would read
--    the damaged page, and error 824 (severity 24) would close the connection.
SELECT SUM(rows) AS rows_before_repair
FROM PachadataTraining_Ex11.sys.partitions
WHERE object_id = OBJECT_ID(N'PachadataTraining_Ex11.dbo.PaymentArchive') AND index_id = 1;
GO
-- 4. The repair, in single-user mode.
USE master;
ALTER DATABASE PachadataTraining_Ex11 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DBCC CHECKDB (N'PachadataTraining_Ex11', REPAIR_ALLOW_DATA_LOSS) WITH NO_INFOMSGS, ALL_ERRORMSGS;
ALTER DATABASE PachadataTraining_Ex11 SET MULTI_USER;
GO
-- 5. The loss: the archive against the table it was copied from. In production, no such
--    table exists, and the lost payments are only known through a restore.
USE PachadataTraining_Ex11;
SELECT COUNT(*) AS rows_after_repair FROM dbo.PaymentArchive;
SELECT COUNT(*) AS lost_payments, MIN(p.PaymentId) AS first_lost, MAX(p.PaymentId) AS last_lost,
       SUM(p.Amount) AS lost_amount
FROM Enrollment.Payment AS p
WHERE NOT EXISTS (SELECT * FROM dbo.PaymentArchive AS a WHERE a.PaymentId = p.PaymentId);
DBCC CHECKDB WITH NO_INFOMSGS;
SELECT DATABASEPROPERTYEX(N'PachadataTraining_Ex11', 'LastGoodCheckDbTime') AS last_good_checkdb;
GO
