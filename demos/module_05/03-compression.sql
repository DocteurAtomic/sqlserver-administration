-- Clip 5.3: data compression. Runs on the lab, in one session, after
-- 02-tables-and-constraints.sql. It takes about a minute: the estimates sample the tables,
-- and part 3 rebuilds 7.8 million rows.
-- The operations team wants the space back without buying disk. Two candidates: the
-- prospects of clip 5.1, not compressed, and Elearning.Activity, the largest table,
-- delivered in ROW compression.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The compression of every index of the two tables, and their size.
SELECT OBJECT_SCHEMA_NAME(i.object_id) + N'.' + OBJECT_NAME(i.object_id) AS table_name,
       i.index_id, i.name AS index_name, i.type_desc, p.data_compression_desc,
       ps.used_page_count, ps.used_page_count * 8 AS used_kb
FROM sys.indexes AS i
JOIN sys.partitions AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
JOIN sys.dm_db_partition_stats AS ps ON ps.partition_id = p.partition_id
WHERE i.object_id IN (OBJECT_ID(N'Contact.ProspectUS'), OBJECT_ID(N'Elearning.Activity'))
ORDER BY table_name, i.index_id;
GO
-- 2. The estimates. The procedure copies a sample of each index into tempdb, compresses it
--    and extrapolates; the table itself is not touched.
EXEC sys.sp_estimate_data_compression_savings
     @schema_name = N'Contact', @object_name = N'ProspectUS', @index_id = NULL,
     @partition_number = NULL, @data_compression = N'PAGE';
EXEC sys.sp_estimate_data_compression_savings
     @schema_name = N'Elearning', @object_name = N'Activity', @index_id = NULL,
     @partition_number = NULL, @data_compression = N'PAGE';
-- What Activity would weigh without the ROW compression it was delivered with.
EXEC sys.sp_estimate_data_compression_savings
     @schema_name = N'Elearning', @object_name = N'Activity', @index_id = 0,
     @partition_number = NULL, @data_compression = N'NONE';
GO
-- 3. PAGE on the heap of Activity. Rebuilding a heap rebuilds its nonclustered indexes, but
--    they keep their own compression.
ALTER TABLE Elearning.Activity REBUILD WITH (DATA_COMPRESSION = PAGE);
SELECT i.index_id, i.name AS index_name, p.data_compression_desc, ps.used_page_count,
       ps.used_page_count * 8 AS used_kb
FROM sys.indexes AS i
JOIN sys.partitions AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
JOIN sys.dm_db_partition_stats AS ps ON ps.partition_id = p.partition_id
WHERE i.object_id = OBJECT_ID(N'Elearning.Activity')
ORDER BY i.index_id;
GO
-- 4. The nonclustered index, compressed by its own rebuild.
ALTER INDEX pk_Activity ON Elearning.Activity REBUILD WITH (DATA_COMPRESSION = PAGE);
SELECT i.index_id, i.name AS index_name, p.data_compression_desc, ps.used_page_count,
       ps.used_page_count * 8 AS used_kb
FROM sys.indexes AS i
JOIN sys.partitions AS p ON p.object_id = i.object_id AND p.index_id = i.index_id
JOIN sys.dm_db_partition_stats AS ps ON ps.partition_id = p.partition_id
WHERE i.object_id = OBJECT_ID(N'Elearning.Activity')
ORDER BY i.index_id;
GO
-- 5. The limit of PAGE on a heap: the pages that ordinary inserts add are not PAGE
--    compressed until the next rebuild; an insert WITH (TABLOCK) compresses them. Shown on a
--    load table with the columns of Activity, created PAGE compressed, then dropped.
CREATE TABLE dbo.ActivityLoad (
    ActivityId      bigint       NOT NULL,
    EventTime       datetime2(0) NOT NULL,
    ContactId       int          NOT NULL,
    EnrollmentId    int          NOT NULL,
    ModuleId        int          NULL,
    EventTypeCode   char(4)      NOT NULL,
    Step            smallint     NULL,
    DurationSeconds int          NULL,
    Score           tinyint      NULL,
    Device          char(1)      NULL
) WITH (DATA_COMPRESSION = PAGE);
INSERT INTO dbo.ActivityLoad
SELECT TOP (500000) ActivityId, EventTime, ContactId, EnrollmentId, ModuleId, EventTypeCode,
       Step, DurationSeconds, Score, Device
FROM Elearning.Activity
ORDER BY ActivityId;
SELECT N'INSERT' AS load_type, page_count, compressed_page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.ActivityLoad'), 0, NULL, 'DETAILED');
TRUNCATE TABLE dbo.ActivityLoad;
INSERT INTO dbo.ActivityLoad WITH (TABLOCK)
SELECT TOP (500000) ActivityId, EventTime, ContactId, EnrollmentId, ModuleId, EventTypeCode,
       Step, DurationSeconds, Score, Device
FROM Elearning.Activity
ORDER BY ActivityId;
SELECT N'INSERT WITH (TABLOCK)' AS load_type, page_count, compressed_page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.ActivityLoad'), 0, NULL, 'DETAILED');
DROP TABLE dbo.ActivityLoad;
GO
