-- Clip 4.4: the space and the shrink. Runs on the lab, in one session, after
-- 03-database-options.sql. It takes about a minute.
-- The e-learning team purges the activity before 2020 from the archive, and asks for the
-- disk space back. Then the log, grown by small steps during the load, is set right.
USE PachadataArchive;
SET NOCOUNT ON;
GO
-- 1. The space of each file, and the free space of the volume under it.
SELECT f.name AS file_name, f.type_desc, f.size / 128 AS size_mb,
       FILEPROPERTY(f.name, 'SpaceUsed') / 128 AS used_mb,
       (f.size - FILEPROPERTY(f.name, 'SpaceUsed')) / 128 AS free_mb,
       v.volume_mount_point, v.available_bytes / 1048576 AS volume_free_mb
FROM sys.database_files AS f
CROSS APPLY sys.dm_os_volume_stats(DB_ID(), f.file_id) AS v
ORDER BY f.file_id;
GO
-- 2. The purge: 1.7 million rows, the oldest keys, at the start of the clustered index.
DELETE FROM dbo.Activity WHERE EventTime < '2020-01-01';
SELECT @@ROWCOUNT AS rows_deleted;
CHECKPOINT;
SELECT name AS file_name, size / 128 AS size_mb,
       FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files
WHERE type_desc = N'ROWS'
ORDER BY file_id;
SELECT CAST(avg_fragmentation_in_percent AS decimal(5, 2)) AS fragmentation_pct, page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.Activity'), 1, NULL, 'LIMITED');
GO
-- 3. The shrink of the two data files, file by file, with a target in MB. It waits at low
--    priority and gives up rather than block the other sessions.
DBCC SHRINKFILE (PachadataArchive_a1, 64) WITH WAIT_AT_LOW_PRIORITY (ABORT_AFTER_WAIT = SELF);
DBCC SHRINKFILE (PachadataArchive_a2, 64) WITH WAIT_AT_LOW_PRIORITY (ABORT_AFTER_WAIT = SELF);
SELECT name AS file_name, size / 128 AS size_mb,
       FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files
WHERE type_desc = N'ROWS'
ORDER BY file_id;
SELECT CAST(avg_fragmentation_in_percent AS decimal(5, 2)) AS fragmentation_pct, page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.Activity'), 1, NULL, 'LIMITED');
GO
-- 4. REORGANIZE puts the leaf pages back in order where they are, without a second copy of
--    the index: the files keep their size. (A REBUILD needs free space for the new copy:
--    see SORTIES.md.)
ALTER INDEX PK_Activity ON dbo.Activity REORGANIZE;
SELECT name AS file_name, size / 128 AS size_mb,
       FILEPROPERTY(name, 'SpaceUsed') / 128 AS used_mb
FROM sys.database_files
WHERE type_desc = N'ROWS'
ORDER BY file_id;
SELECT CAST(avg_fragmentation_in_percent AS decimal(5, 2)) AS fragmentation_pct, page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID(N'dbo.Activity'), 1, NULL, 'LIMITED');
GO
-- 5. The log: where the active VLF is, then the shrink. The file can only be cut after the
--    last active VLF.
CHECKPOINT;
SELECT COUNT(*) AS vlf_count, SUM(CAST(vlf_active AS int)) AS active_vlf,
       MAX(CASE WHEN vlf_active = 1 THEN vlf_sequence_number END) AS active_sequence
FROM sys.dm_db_log_info(DB_ID());
DBCC SHRINKFILE (PachadataArchive_log, 1);
SELECT size / 128 AS log_mb, (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) AS vlf_count
FROM sys.database_files WHERE type_desc = N'LOG';
GO
-- 6. The log set back to its working size in one operation, with a growth in MB.
ALTER DATABASE PachadataArchive
    MODIFY FILE (NAME = PachadataArchive_log, SIZE = 1024MB, FILEGROWTH = 512MB);
SELECT size / 128 AS log_mb, growth / 128 AS growth_mb,
       (SELECT COUNT(*) FROM sys.dm_db_log_info(DB_ID())) AS vlf_count
FROM sys.database_files WHERE type_desc = N'LOG';
GO
-- 7. What the team asked for: the archive, its files, its log and its options.
SELECT f.name AS file_name, f.type_desc, fg.name AS filegroup_name, f.size / 128 AS size_mb,
       FILEPROPERTY(f.name, 'SpaceUsed') / 128 AS used_mb, f.growth / 128 AS growth_mb
FROM sys.database_files AS f
LEFT JOIN sys.filegroups AS fg ON fg.data_space_id = f.data_space_id
ORDER BY f.file_id;
SELECT d.recovery_model_desc, d.is_auto_close_on, d.is_auto_shrink_on, d.page_verify_option_desc,
       (SELECT COUNT(*) FROM sys.dm_db_log_info(d.database_id)) AS vlf_count,
       (SELECT COUNT_BIG(*) FROM dbo.Activity) AS activity_rows
FROM sys.databases AS d
WHERE d.database_id = DB_ID();
GO
