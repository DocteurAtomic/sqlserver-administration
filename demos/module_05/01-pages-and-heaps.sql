-- Clip 5.1: pages, extents, heaps and clustered indexes. Runs on the lab, in one session,
-- after 00-setup.sql. It takes between five and twenty seconds.
-- The operations team asks where the space of PachadataTraining goes, table by table. The
-- marketing team adds that counting its US prospects reads more pages every week.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. Where the space goes: the ten largest tables, their structure and compression, and
--    their pages by allocation unit (rows, LOB, row overflow).
SELECT TOP (10)
       CONCAT(OBJECT_SCHEMA_NAME(p.object_id), N'.', OBJECT_NAME(p.object_id)) AS table_name,
       MAX(i.type_desc) AS structure,
       MAX(p.data_compression_desc) AS compression,
       COUNT(DISTINCT p.partition_number) AS partitions,
       SUM(CASE WHEN au.type = 1 THEN p.rows END) AS row_count,
       SUM(CASE WHEN au.type = 1 THEN au.used_pages END) AS in_row_pages,
       SUM(CASE WHEN au.type = 2 THEN au.used_pages END) AS lob_pages,
       SUM(CASE WHEN au.type = 3 THEN au.used_pages END) AS overflow_pages,
       SUM(au.used_pages) / 128 AS used_mb
FROM sys.partitions AS p
JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
JOIN sys.allocation_units AS au
  ON au.container_id = CASE au.type WHEN 2 THEN p.partition_id ELSE p.hobt_id END
WHERE p.index_id IN (0, 1, 5)       -- the table itself: heap, clustered or clustered columnstore
  AND OBJECTPROPERTY(p.object_id, 'IsMSShipped') = 0
GROUP BY p.object_id
ORDER BY SUM(au.used_pages) DESC;
GO
-- 2. One page of each structure. %%physloc%% and sys.fn_PhysLocCracker are undocumented:
--    they give the file and page of a row, here the first row read.
DECLARE @file int, @page int;
SELECT TOP (1) @file = pl.file_id, @page = pl.page_id
FROM Contact.ProspectUS AS p
CROSS APPLY sys.fn_PhysLocCracker(%%physloc%%) AS pl;
SELECT N'Contact.ProspectUS' AS table_name, page_id, page_type_desc, page_level, slot_count,
       free_bytes, index_id, pfs_page_id, gam_page_id, sgam_page_id
FROM sys.dm_db_page_info(DB_ID(), @file, @page, 'DETAILED');
SELECT TOP (1) @file = pl.file_id, @page = pl.page_id
FROM Marketing.Delivery AS d
CROSS APPLY sys.fn_PhysLocCracker(%%physloc%%) AS pl;
SELECT N'Marketing.Delivery' AS table_name, page_id, page_type_desc, page_level, slot_count,
       free_bytes, index_id, prev_page_page_id, next_page_page_id
FROM sys.dm_db_page_info(DB_ID(), @file, @page, 'DETAILED');
-- Since SQL Server 2016, a user database allocates uniform extents from the first page.
SELECT name, is_mixed_page_allocation_on
FROM sys.databases
WHERE database_id = DB_ID();
GO
-- 3. The heaps of the database, and their forwarded records. A heap is index_id 0;
--    forwarded_record_count is only computed in SAMPLED or DETAILED mode.
SELECT CONCAT(OBJECT_SCHEMA_NAME(ps.object_id), N'.', OBJECT_NAME(ps.object_id)) AS heap_name,
       ps.partition_number, ps.page_count, ps.record_count, ps.forwarded_record_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'DETAILED') AS ps
WHERE ps.index_id = 0
  AND ps.alloc_unit_type_desc = N'IN_ROW_DATA'
  AND ps.page_count > 100
ORDER BY ps.forwarded_record_count DESC, ps.page_count DESC;
GO
-- 4. What a forwarded record costs: the count of the marketing team, with the pages read.
SET STATISTICS IO ON;
SELECT COUNT(*) AS prospects_with_email FROM Contact.ProspectUS WHERE Email LIKE '%@%';
SET STATISTICS IO OFF;
SELECT forwarded_fetch_count
FROM sys.dm_db_index_operational_stats(DB_ID(), OBJECT_ID(N'Contact.ProspectUS'), 0, NULL);
GO
-- 5. The correction: rebuild the heap. Its nonclustered index is rebuilt with it.
ALTER TABLE Contact.ProspectUS REBUILD;
SELECT index_type_desc, index_id, page_count, record_count, forwarded_record_count,
       CAST(avg_page_space_used_in_percent AS decimal(5, 2)) AS page_fullness_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'Contact.ProspectUS'), NULL, NULL, 'DETAILED')
WHERE index_level = 0;
SET STATISTICS IO ON;
SELECT COUNT(*) AS prospects_with_email FROM Contact.ProspectUS WHERE Email LIKE '%@%';
SET STATISTICS IO OFF;
GO
