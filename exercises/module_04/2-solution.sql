-- Module 4 exercise: solution. Runs on your lab, in one session, after 1-start.sql.
-- It takes about a minute, and drops at the end the two databases of the exercise.
-- Part 3 opens a transaction and reads the log from the same session; on your lab, do it
-- from two query windows.
USE master;
SET NOCOUNT ON;
GO
-- Part 1. A small PRIMARY for the catalog, a default filegroup of two files of the same
-- size, and a log that grows by 1 MB, as on old databases.
CREATE DATABASE MarketingArchive_Ex04
ON PRIMARY
    (NAME = MarketingArchive_Ex04_sys, FILENAME = N'/var/opt/mssql/data/MarketingArchive_Ex04_sys.mdf',
     SIZE = 16MB, FILEGROWTH = 16MB),
FILEGROUP DELIVERY DEFAULT
    (NAME = MarketingArchive_Ex04_d1, FILENAME = N'/var/opt/mssql/data/MarketingArchive_Ex04_d1.ndf',
     SIZE = 64MB, FILEGROWTH = 64MB),
    (NAME = MarketingArchive_Ex04_d2, FILENAME = N'/var/opt/mssql/data/MarketingArchive_Ex04_d2.ndf',
     SIZE = 64MB, FILEGROWTH = 64MB)
LOG ON
    (NAME = MarketingArchive_Ex04_log, FILENAME = N'/var/opt/mssql/data/MarketingArchive_Ex04_log.ldf',
     SIZE = 8MB, FILEGROWTH = 1MB);
GO
ALTER DATABASE MarketingArchive_Ex04 SET RECOVERY SIMPLE;
GO
USE MarketingArchive_Ex04;
CREATE TABLE dbo.Delivery (
    DeliveryId int          NOT NULL CONSTRAINT PK_Delivery PRIMARY KEY CLUSTERED,
    CampaignId int          NOT NULL,
    ContactId  int          NOT NULL,
    SendDate   datetime2(0) NOT NULL,
    Opened     bit          NOT NULL,
    Clicked    bit          NOT NULL
);
INSERT INTO dbo.Delivery
SELECT DeliveryId, CampaignId, ContactId, SendDate, Opened, Clicked
FROM PachadataTraining.Marketing.Delivery
WHERE SendDate >= '2023-01-01' AND SendDate < '2025-01-01';
-- The table, created without ON, is in the default filegroup.
SELECT i.name AS index_name, ds.name AS data_space
FROM sys.indexes AS i
JOIN sys.data_spaces AS ds ON ds.data_space_id = i.data_space_id
WHERE i.object_id = OBJECT_ID(N'dbo.Delivery');
-- Proportional fill: the same share in d1 and d2.
SELECT name AS file_name, size / 128 AS size_mb, FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files WHERE type_desc = N'ROWS' ORDER BY file_id;
GO
-- A third file, twice as large, then 2025.
ALTER DATABASE MarketingArchive_Ex04
    ADD FILE (NAME = MarketingArchive_Ex04_d3, FILENAME = N'/var/opt/mssql/data/MarketingArchive_Ex04_d3.ndf',
              SIZE = 128MB, FILEGROWTH = 64MB)
    TO FILEGROUP DELIVERY;
GO
INSERT INTO dbo.Delivery
SELECT DeliveryId, CampaignId, ContactId, SendDate, Opened, Clicked
FROM PachadataTraining.Marketing.Delivery
WHERE SendDate >= '2025-01-01' AND SendDate < '2026-01-01';
-- d3 had the most free space: it gets the largest share. d1 and d2 keep their old pages.
SELECT name AS file_name, size / 128 AS size_mb, FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files WHERE type_desc = N'ROWS' ORDER BY file_id;
GO
-- Part 2. The log after the two loads: its size, its growths, its VLF.
WAITFOR DELAY '00:00:05';   -- the default trace is written by buffers
DECLARE @trace nvarchar(260) = (SELECT path FROM sys.traces WHERE is_default = 1);
SELECT COUNT(*) AS log_growths, SUM(CAST(IntegerData AS bigint)) * 8 / 1024 AS mb_added
FROM sys.fn_trace_gettable(@trace, DEFAULT)
WHERE EventClass = 93 AND DatabaseName = DB_NAME()
  AND StartTime >= (SELECT create_date FROM sys.databases WHERE database_id = DB_ID());
SELECT (SELECT size / 128 FROM sys.database_files WHERE type_desc = N'LOG') AS log_mb,
       COUNT(*) AS vlf_count
FROM sys.dm_db_log_info(DB_ID());
GO
-- A manual growth of exactly 64 MB, the zeroing written to the error log for this session.
DECLARE @vlf_before int = (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID()));
DECLARE @size int = (SELECT size / 128 FROM sys.database_files WHERE type_desc = N'LOG');
DECLARE @sql nvarchar(400) = N'ALTER DATABASE MarketingArchive_Ex04 MODIFY FILE (NAME = MarketingArchive_Ex04_log, SIZE = '
        + CAST(@size + 64 AS nvarchar(10)) + N'MB);';
DECLARE @since datetime = GETDATE();
DBCC TRACEON (3004, 3605);
EXEC (@sql);
DBCC TRACEOFF (3004, 3605);
SELECT @size AS log_mb_before, @size + 64 AS log_mb_after, @vlf_before AS vlf_before,
       (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) AS vlf_after;
EXEC sys.xp_readerrorlog 0, 1, N'Zeroing', N'MarketingArchive_Ex04_log', @since, NULL, N'asc';
GO
-- Part 3. An open transaction holds the log; the checkpoint frees nothing.
BEGIN TRANSACTION;
UPDATE dbo.Delivery SET CampaignId = CampaignId + 1 WHERE SendDate < '2025-01-01';
CHECKPOINT;
SELECT d.log_reuse_wait_desc, u.total_log_size_in_bytes / 1048576 AS log_mb,
       CAST(u.used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM sys.databases AS d CROSS JOIN sys.dm_db_log_space_usage AS u
WHERE d.database_id = DB_ID();
ROLLBACK;
CHECKPOINT;
SELECT d.log_reuse_wait_desc, u.total_log_size_in_bytes / 1048576 AS log_mb,
       CAST(u.used_log_space_in_percent AS decimal(5, 1)) AS used_pct
FROM sys.databases AS d CROSS JOIN sys.dm_db_log_space_usage AS u
WHERE d.database_id = DB_ID();
GO
-- Shrink the log, then set it back to a working size in one operation.
DBCC SHRINKFILE (MarketingArchive_Ex04_log, 1);
SELECT size / 128 AS log_mb, (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) AS vlf_count
FROM sys.database_files WHERE type_desc = N'LOG';
ALTER DATABASE MarketingArchive_Ex04
    MODIFY FILE (NAME = MarketingArchive_Ex04_log, SIZE = 256MB, FILEGROWTH = 128MB);
SELECT size / 128 AS log_mb, growth / 128 AS growth_mb,
       (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) AS vlf_count
FROM sys.database_files WHERE type_desc = N'LOG';
GO
-- Part 4. Purge 2023 and 2024, then the wrong order: REBUILD first, shrink after.
DELETE FROM dbo.Delivery WHERE SendDate < '2025-01-01';
CHECKPOINT;
ALTER INDEX PK_Delivery ON dbo.Delivery REBUILD;
SELECT name AS file_name, size / 128 AS size_mb, FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files WHERE type_desc = N'ROWS' ORDER BY file_id;
SELECT CAST(avg_fragmentation_in_percent AS decimal(5, 2)) AS fragmentation_pct, page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.Delivery'), 1, NULL, 'LIMITED');
GO
-- The shrink moves the pages that the rebuild had just put in order.
DBCC SHRINKFILE (MarketingArchive_Ex04_d1, 32) WITH WAIT_AT_LOW_PRIORITY (ABORT_AFTER_WAIT = SELF);
DBCC SHRINKFILE (MarketingArchive_Ex04_d2, 32) WITH WAIT_AT_LOW_PRIORITY (ABORT_AFTER_WAIT = SELF);
DBCC SHRINKFILE (MarketingArchive_Ex04_d3, 32) WITH WAIT_AT_LOW_PRIORITY (ABORT_AFTER_WAIT = SELF);
SELECT name AS file_name, size / 128 AS size_mb, FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files WHERE type_desc = N'ROWS' ORDER BY file_id;
SELECT CAST(avg_fragmentation_in_percent AS decimal(5, 2)) AS fragmentation_pct, page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.Delivery'), 1, NULL, 'LIMITED');
GO
-- REORGANIZE puts the pages back in order where they are: the files keep their size.
ALTER INDEX PK_Delivery ON dbo.Delivery REORGANIZE;
SELECT name AS file_name, size / 128 AS size_mb, FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files WHERE type_desc = N'ROWS' ORDER BY file_id;
SELECT CAST(avg_fragmentation_in_percent AS decimal(5, 2)) AS fragmentation_pct, page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.Delivery'), 1, NULL, 'LIMITED');
GO
-- Part 5. The options of every user database. The copy, closed by AUTO_CLOSE, reads a NULL
-- collation.
USE master;
WAITFOR DELAY '00:00:02';
SELECT name, SUSER_SNAME(owner_sid) AS owner_name, is_auto_close_on, is_auto_shrink_on,
       page_verify_option_desc, is_auto_create_stats_on, is_auto_update_stats_on,
       collation_name, DATABASEPROPERTYEX(name, 'Collation') AS collation_property
FROM sys.databases
WHERE database_id > 4
ORDER BY name;
-- The corrections, generated for every database that needs one.
SELECT d.name,
       N'ALTER DATABASE ' + QUOTENAME(d.name) + N' SET '
       + STUFF(  CASE WHEN d.is_auto_close_on = 1 THEN N', AUTO_CLOSE OFF' ELSE N'' END
               + CASE WHEN d.is_auto_shrink_on = 1 THEN N', AUTO_SHRINK OFF' ELSE N'' END
               + CASE WHEN d.page_verify_option <> 2 THEN N', PAGE_VERIFY CHECKSUM' ELSE N'' END
               + CASE WHEN d.is_auto_create_stats_on = 0 THEN N', AUTO_CREATE_STATISTICS ON' ELSE N'' END
               + CASE WHEN d.is_auto_update_stats_on = 0 THEN N', AUTO_UPDATE_STATISTICS ON' ELSE N'' END,
               1, 2, N'') + N';' AS correction
FROM sys.databases AS d
WHERE d.database_id > 4
  AND d.source_database_id IS NULL
  AND (d.is_auto_close_on = 1 OR d.is_auto_shrink_on = 1 OR d.page_verify_option <> 2
       OR d.is_auto_create_stats_on = 0 OR d.is_auto_update_stats_on = 0);
GO
ALTER DATABASE PachadataTraining_Ex04
    SET AUTO_CLOSE OFF, AUTO_SHRINK OFF, PAGE_VERIFY CHECKSUM,
        AUTO_CREATE_STATISTICS ON, AUTO_UPDATE_STATISTICS ON;
ALTER AUTHORIZATION ON DATABASE::PachadataTraining_Ex04 TO sa;
SELECT name, SUSER_SNAME(owner_sid) AS owner_name, is_auto_close_on, is_auto_shrink_on,
       page_verify_option_desc, is_auto_create_stats_on, is_auto_update_stats_on, collation_name
FROM sys.databases
WHERE name = N'PachadataTraining_Ex04';
GO
-- Cleanup: the two databases of the exercise.
ALTER DATABASE MarketingArchive_Ex04 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE MarketingArchive_Ex04;
ALTER DATABASE PachadataTraining_Ex04 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining_Ex04;
SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;
GO
