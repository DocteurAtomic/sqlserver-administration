-- Clip 11.1: checking the integrity of PachadataTraining. Runs on the lab, in one session,
-- after 00-setup.sql. Reads only. It takes about half a minute.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The last check that found no error. A restored database keeps the date written in its
--    boot page by the server it comes from: here, the day the delivered backup was checked.
SELECT DATABASEPROPERTYEX(N'PachadataTraining', 'LastGoodCheckDbTime') AS last_good_checkdb;
GO
-- 2. The space CHECKDB needs in tempdb, estimated without checking anything.
DBCC CHECKDB (N'PachadataTraining') WITH ESTIMATEONLY;
GO
-- 3. The physical check only (page checksums, headers, allocation), then the full check.
DECLARE @t datetime2 = SYSDATETIME();
DBCC CHECKDB (N'PachadataTraining') WITH NO_INFOMSGS, PHYSICAL_ONLY;
SELECT DATEDIFF(millisecond, @t, SYSDATETIME()) AS physical_only_ms;
SET @t = SYSDATETIME();
DBCC CHECKDB (N'PachadataTraining') WITH NO_INFOMSGS;
SELECT DATEDIFF(millisecond, @t, SYSDATETIME()) AS full_check_ms;
GO
-- 4. A check without error moves the date to now.
SELECT DATABASEPROPERTYEX(N'PachadataTraining', 'LastGoodCheckDbTime') AS last_good_checkdb;
GO
