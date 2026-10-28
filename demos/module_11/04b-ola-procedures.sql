-- Clip 11.4: DatabaseIntegrityCheck and IndexOptimize called by hand, then dbo.CommandLog.
-- Runs on the lab, in one session, after 02a and 03 (the indexes of Contact.Contact and
-- Enrollment.InvoiceLine are no longer fragmented). About ten seconds.
USE DBA;
SET NOCOUNT ON;
GO
-- The last row of CommandLog before this script, to read only what follows.
DROP TABLE IF EXISTS #start;
SELECT ISNULL(MAX(ID), 0) AS last_id INTO #start FROM dbo.CommandLog;
GO
-- 1. The integrity of two databases, each command logged in dbo.CommandLog.
EXECUTE dbo.DatabaseIntegrityCheck
    @Databases = N'PachadataTraining, DBA',
    @CheckCommands = N'CHECKDB',
    @NoInformationalMessages = N'Y',
    @LogToTable = N'Y';
GO
-- 2. The indexes and the statistics of PachadataTraining: example B of Ola Hallengren's
--    documentation, with the statistics that changed since they were computed.
EXECUTE dbo.IndexOptimize
    @Databases = N'PachadataTraining',
    @FragmentationLow = NULL,
    @FragmentationMedium = N'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
    @FragmentationHigh = N'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
    @FragmentationLevel1 = 5,
    @FragmentationLevel2 = 30,
    @UpdateStatistics = N'ALL',
    @OnlyModifiedStatistics = N'Y',
    @LogToTable = N'Y';
GO
-- 3. What was done, one row per command: for an index, its size and fragmentation at the
--    moment of the decision are kept in ExtendedInfo.
SELECT DatabaseName, ObjectName, IndexName, StatisticsName, CommandType,
       ExtendedInfo.value('(ExtendedInfo/PageCount)[1]', 'int') AS page_count,
       ExtendedInfo.value('(ExtendedInfo/Fragmentation)[1]', 'decimal(5,1)') AS fragmentation_pct,
       DATEDIFF(millisecond, StartTime, EndTime) AS duration_ms, ErrorNumber
FROM dbo.CommandLog
WHERE ID > (SELECT last_id FROM #start)
  AND CommandType IN (N'DBCC_CHECKDB', N'ALTER_INDEX', N'UPDATE_STATISTICS')
ORDER BY ID;
GO
