-- Clip 11.2: measuring the indexes of PachadataTraining, then a reorganization and a rebuild,
-- and the log each one writes. Runs on the lab, in one session, after 00-setup.sql.
-- It takes about half a minute. For the log measurement, the database goes to the FULL
-- recovery model, as in production, with a full backup in /var/opt/mssql/backup/module_11;
-- it goes back to SIMPLE at the end. 99-cleanup.sql deletes the backup files.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. Fragmentation and page density of the leaf level. SAMPLED reads a sample of the leaf
--    pages; LIMITED, the mode of the maintenance scripts, does not return the density.
SELECT OBJECT_SCHEMA_NAME(ps.object_id) + N'.' + OBJECT_NAME(ps.object_id) AS table_name,
       i.name AS index_name, ps.page_count,
       CAST(ps.avg_fragmentation_in_percent AS decimal(5,1)) AS fragmentation_pct,
       CAST(ps.avg_page_space_used_in_percent AS decimal(5,1)) AS page_density_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') AS ps
JOIN sys.indexes AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.index_level = 0 AND ps.page_count > 1000 AND i.type IN (1, 2)
ORDER BY ps.avg_fragmentation_in_percent DESC;
GO
-- 2. The FULL recovery model and its first full backup: from now on, the log keeps what the
--    index operations write until a log backup.
USE master;
ALTER DATABASE PachadataTraining SET RECOVERY FULL;
BACKUP DATABASE PachadataTraining TO DISK = N'/var/opt/mssql/backup/module_11/PachadataTraining_full.bak'
    WITH INIT, FORMAT, CHECKSUM, COMPRESSION;
BACKUP LOG PachadataTraining TO DISK = N'/var/opt/mssql/backup/module_11/PachadataTraining_log1.trn'
    WITH INIT, FORMAT;
GO
USE PachadataTraining;
GO
-- 3. REORGANIZE: online, single-threaded, page by page, in short transactions.
DECLARE @t datetime2 = SYSDATETIME(),
        @log0 bigint = (SELECT used_log_space_in_bytes FROM sys.dm_db_log_space_usage);
ALTER INDEX pk_Contact ON Contact.Contact REORGANIZE;
SELECT N'REORGANIZE pk_Contact' AS operation,
       DATEDIFF(millisecond, @t, SYSDATETIME()) AS duration_ms,
       CAST(((SELECT used_log_space_in_bytes FROM sys.dm_db_log_space_usage) - @log0) / 1048576.0
            AS decimal(9,1)) AS log_written_mb;
BACKUP LOG PachadataTraining TO DISK = N'/var/opt/mssql/backup/module_11/PachadataTraining_log2.trn'
    WITH INIT, FORMAT;
GO
-- 4. REBUILD: a new copy of the index, then the old one dropped. ONLINE = ON keeps the table
--    readable and writable (Enterprise and Developer editions).
DECLARE @t datetime2 = SYSDATETIME(),
        @log0 bigint = (SELECT used_log_space_in_bytes FROM sys.dm_db_log_space_usage);
ALTER INDEX pk_InvoiceLine ON Enrollment.InvoiceLine REBUILD WITH (ONLINE = ON);
SELECT N'REBUILD pk_InvoiceLine' AS operation,
       DATEDIFF(millisecond, @t, SYSDATETIME()) AS duration_ms,
       CAST(((SELECT used_log_space_in_bytes FROM sys.dm_db_log_space_usage) - @log0) / 1048576.0
            AS decimal(9,1)) AS log_written_mb;
BACKUP LOG PachadataTraining TO DISK = N'/var/opt/mssql/backup/module_11/PachadataTraining_log3.trn'
    WITH INIT, FORMAT;
GO
-- 5. The two indexes after the operations, and their statistics: the rebuild recomputed the
--    statistic of its index on every row, the reorganization left it as it was.
SELECT OBJECT_SCHEMA_NAME(ps.object_id) + N'.' + OBJECT_NAME(ps.object_id) AS table_name,
       ps.page_count,
       CAST(ps.avg_fragmentation_in_percent AS decimal(5,1)) AS fragmentation_pct,
       CAST(ps.avg_page_space_used_in_percent AS decimal(5,1)) AS page_density_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'SAMPLED') AS ps
WHERE ps.index_level = 0 AND ps.index_id = 1
  AND ps.object_id IN (OBJECT_ID(N'Contact.Contact'), OBJECT_ID(N'Enrollment.InvoiceLine'));
SELECT OBJECT_NAME(s.object_id) AS table_name, s.name AS statistic, p.last_updated,
       p.rows, p.rows_sampled
FROM sys.stats AS s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) AS p
WHERE s.name IN (N'pk_Contact', N'pk_InvoiceLine');
GO
-- 6. Back to the recovery model of the delivered database.
USE master;
ALTER DATABASE PachadataTraining SET RECOVERY SIMPLE;
GO
