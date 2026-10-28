-- ci: skip
-- Clip 3.2: model as the template of PachaData. Changes model, an instance-wide setting: it
-- runs on a throwaway container (02-throwaway-container.sh), never on the lab of the course.
-- 99-cleanup.sql gives model back its delivered settings if you played it on your lab.
-- A few seconds.
USE master;
SET NOCOUNT ON;
GO
-- 1. Before: model as installed, FULL, 8 MB files growing by 64 MB.
SELECT d.name, d.recovery_model_desc, mf.name AS logical_name, mf.size / 128 AS size_mb,
       mf.growth / 128 AS growth_mb
FROM sys.databases AS d
JOIN sys.master_files AS mf ON mf.database_id = d.database_id
WHERE d.name = N'model';
GO
-- 2. The rule of PachaData: a new database starts in SIMPLE, and enters FULL when the DBA puts
--    it in the backup plan (module 12); its files start at 64 MB and grow by 64 MB.
ALTER DATABASE model SET RECOVERY SIMPLE;
ALTER DATABASE model MODIFY FILE (NAME = N'modeldev', SIZE = 64MB, FILEGROWTH = 64MB);
ALTER DATABASE model MODIFY FILE (NAME = N'modellog', SIZE = 64MB, FILEGROWTH = 64MB);
GO
-- 3. The developer of the web site creates his database, with no option. model is copied at
--    creation only: a database created before the change keeps what it had.
IF DB_ID(N'WebShop') IS NOT NULL
    DROP DATABASE WebShop;
GO
CREATE DATABASE WebShop;
GO
SELECT d.name, d.recovery_model_desc, mf.name AS logical_name, mf.size / 128 AS size_mb,
       mf.growth / 128 AS growth_mb
FROM sys.databases AS d
JOIN sys.master_files AS mf ON mf.database_id = d.database_id
WHERE d.name IN (N'model', N'WebShop')
ORDER BY d.database_id, mf.file_id;
GO
-- 4. model has changed: back it up, as after every change of a system database.
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_03';
BACKUP DATABASE model TO DISK = N'/var/opt/mssql/backup/module_03/model.bak'
    WITH INIT, CHECKSUM;
GO
SELECT bs.database_name, bs.type, bs.backup_finish_date, bs.server_name,
       bmf.physical_device_name
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'model'
  AND bs.server_name = @@SERVERNAME;
GO
