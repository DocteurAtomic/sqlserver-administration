-- Clip 12.4: backup compression. Runs on the lab, in one session, after 03-stripes-mirror.sql
-- (it also runs alone). About fifteen seconds.
-- Five copy-only backups of the same database, each in a new file (FORMAT): the algorithm
-- and the level are kept by the media set at its creation, a new file avoids that trap.
-- The duration is measured around each BACKUP, to the millisecond; msdb keeps it to the second.
USE master;
SET NOCOUNT ON;
GO
-- 1. The options of the instance that make compression and checksums implicit.
SELECT name, value_in_use
FROM sys.configurations
WHERE name IN (N'backup compression default', N'backup compression algorithm',
               N'backup checksum default');
GO
-- 2. The five backups.
DROP TABLE IF EXISTS #duration;
CREATE TABLE #duration (name nvarchar(128) PRIMARY KEY, ms int);
DECLARE @last_set int = (SELECT MAX(backup_set_id) FROM msdb.dbo.backupset);
DECLARE @t datetime2 = SYSDATETIME();
BACKUP DATABASE PachadataTraining TO DISK = N'/var/opt/mssql/backup/module_12/cmp_none.bak'
    WITH COPY_ONLY, FORMAT, NO_COMPRESSION, NAME = N'NO_COMPRESSION';
INSERT INTO #duration VALUES (N'NO_COMPRESSION', DATEDIFF(ms, @t, SYSDATETIME()));
SET @t = SYSDATETIME();
BACKUP DATABASE PachadataTraining TO DISK = N'/var/opt/mssql/backup/module_12/cmp_xpress.bak'
    WITH COPY_ONLY, FORMAT, COMPRESSION (ALGORITHM = MS_XPRESS), NAME = N'MS_XPRESS';
INSERT INTO #duration VALUES (N'MS_XPRESS', DATEDIFF(ms, @t, SYSDATETIME()));
SET @t = SYSDATETIME();
BACKUP DATABASE PachadataTraining TO DISK = N'/var/opt/mssql/backup/module_12/cmp_zstd.bak'
    WITH COPY_ONLY, FORMAT, COMPRESSION (ALGORITHM = ZSTD), NAME = N'ZSTD';
INSERT INTO #duration VALUES (N'ZSTD', DATEDIFF(ms, @t, SYSDATETIME()));
SET @t = SYSDATETIME();
BACKUP DATABASE PachadataTraining TO DISK = N'/var/opt/mssql/backup/module_12/cmp_zstd_medium.bak'
    WITH COPY_ONLY, FORMAT, COMPRESSION (ALGORITHM = ZSTD, LEVEL = MEDIUM), NAME = N'ZSTD MEDIUM';
INSERT INTO #duration VALUES (N'ZSTD MEDIUM', DATEDIFF(ms, @t, SYSDATETIME()));
SET @t = SYSDATETIME();
BACKUP DATABASE PachadataTraining TO DISK = N'/var/opt/mssql/backup/module_12/cmp_zstd_high.bak'
    WITH COPY_ONLY, FORMAT, COMPRESSION (ALGORITHM = ZSTD, LEVEL = HIGH), NAME = N'ZSTD HIGH';
INSERT INTO #duration VALUES (N'ZSTD HIGH', DATEDIFF(ms, @t, SYSDATETIME()));

-- 3. What msdb recorded: the data read, the size of the file, the ratio.
SELECT b.name, b.compression_algorithm,
       CAST(b.backup_size / 1048576.0 AS decimal(9, 1)) AS data_mb,
       CAST(b.compressed_backup_size / 1048576.0 AS decimal(9, 1)) AS file_mb,
       CAST(b.backup_size / b.compressed_backup_size AS decimal(4, 2)) AS ratio,
       d.ms
FROM msdb.dbo.backupset AS b
JOIN #duration AS d ON d.name = b.name
WHERE b.backup_set_id > @last_set
ORDER BY b.backup_set_id;
GO
