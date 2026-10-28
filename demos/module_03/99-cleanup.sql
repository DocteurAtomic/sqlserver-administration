-- Module 3, cleanup. Runs on the lab, in one session, after the clips and the exercise. A few
-- seconds. On a lab where only the scripts that run alone were played, it changes nothing.
-- It is there for a lab where 02b-model-template.sql or 03a-move-tempdb.sql were played
-- instead of on the throwaway container:
-- 1. Gives model its settings as installed: FULL, two files of 8 MB growing by 64 MB.
--    WebShop, if it exists, is dropped.
-- 2. Puts the files of tempdb back in /var/opt/mssql/data, when they are elsewhere. As for
--    the move, it takes effect at the next start of the instance:
--      sqlcmd ... -Q "SHUTDOWN"  then  docker start sqladmcourse
--    and the files of the other folder are deleted by hand afterwards.
-- 3. Deletes the backup of model under /var/opt/mssql/backup/module_03 and its history.
USE master;
SET NOCOUNT ON;
GO
-- 1. model as installed. A file is never shrunk by MODIFY FILE: SIZE is set only when the
--    file is larger than 8 MB, through DBCC SHRINKFILE.
IF DB_ID(N'WebShop') IS NOT NULL
BEGIN
    ALTER DATABASE WebShop SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE WebShop;
END;
IF DATABASEPROPERTYEX(N'model', 'Recovery') <> N'FULL'
    ALTER DATABASE model SET RECOVERY FULL;
IF EXISTS (SELECT * FROM sys.master_files
           WHERE database_id = 3 AND (growth <> 8192 OR is_percent_growth = 1))
BEGIN
    ALTER DATABASE model MODIFY FILE (NAME = N'modeldev', FILEGROWTH = 64MB);
    ALTER DATABASE model MODIFY FILE (NAME = N'modellog', FILEGROWTH = 64MB);
END;
GO
IF (SELECT size FROM sys.master_files WHERE database_id = 3 AND name = N'modeldev') > 1024
   OR (SELECT size FROM sys.master_files WHERE database_id = 3 AND name = N'modellog') > 1024
BEGIN
    EXEC (N'USE model; DBCC SHRINKFILE (modeldev, 8) WITH NO_INFOMSGS; DBCC SHRINKFILE (modellog, 8) WITH NO_INFOMSGS;');
END;
GO
-- 2. tempdb back in /var/opt/mssql/data, at the next start.
DECLARE @sql nvarchar(max);
SELECT @sql = STRING_AGG(CONVERT(nvarchar(max),
           CONCAT(N'ALTER DATABASE tempdb MODIFY FILE (NAME = ', QUOTENAME(name),
                  N', FILENAME = N''/var/opt/mssql/data/',
                  RIGHT(physical_name, CHARINDEX(N'/', REVERSE(physical_name)) - 1),
                  N''');')), NCHAR(10))
FROM sys.master_files
WHERE database_id = DB_ID(N'tempdb')
  AND physical_name NOT LIKE N'/var/opt/mssql/data/%';
IF @sql IS NOT NULL
    EXEC (@sql);
GO
-- 3. The backup of model, and its history. The folder is read first: the cleanup creates
--    nothing on a lab where it does not exist.
DECLARE @dirs TABLE (subdirectory nvarchar(400), depth int);
INSERT INTO @dirs EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup', 1, 0;
IF EXISTS (SELECT * FROM @dirs WHERE subdirectory = N'module_03')
    EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_03', N'bak', N'2100-01-01', 0;
DECLARE @sets TABLE (backup_set_id int PRIMARY KEY, media_set_id int);
INSERT INTO @sets (backup_set_id, media_set_id)
SELECT bs.backup_set_id, bs.media_set_id
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE bmf.physical_device_name LIKE N'/var/opt/mssql/backup/module_03/%';
DELETE FROM msdb.dbo.backupfile        WHERE backup_set_id IN (SELECT backup_set_id FROM @sets);
DELETE FROM msdb.dbo.backupfilegroup   WHERE backup_set_id IN (SELECT backup_set_id FROM @sets);
DELETE FROM msdb.dbo.backupset         WHERE backup_set_id IN (SELECT backup_set_id FROM @sets);
DELETE FROM msdb.dbo.backupmediafamily WHERE media_set_id IN (SELECT media_set_id FROM @sets);
DELETE FROM msdb.dbo.backupmediaset    WHERE media_set_id IN (SELECT media_set_id FROM @sets);
GO
-- What is left: model as installed, tempdb in its folder (at the next start), no backup.
SELECT d.name, d.recovery_model_desc, mf.name AS logical_name, mf.physical_name,
       mf.size / 128 AS size_mb, mf.growth / 128 AS growth_mb
FROM sys.databases AS d
JOIN sys.master_files AS mf ON mf.database_id = d.database_id
WHERE d.name IN (N'model', N'tempdb')
ORDER BY d.database_id, mf.file_id;
SELECT COUNT(*) AS module_03_backups
FROM msdb.dbo.backupmediafamily
WHERE physical_device_name LIKE N'/var/opt/mssql/backup/module_03/%';
GO
