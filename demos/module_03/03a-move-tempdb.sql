-- ci: skip
-- Clip 3.3: move tempdb to its own folder. Changes master and needs a restart of the
-- instance: it runs on a throwaway container (02-throwaway-container.sh), never on the lab
-- of the course. 99-cleanup.sql moves tempdb back to /var/opt/mssql/data if you played it on
-- your lab; the move back also takes effect at the next restart.
-- On Windows, the folder would be on its own volume (T:\SQLTempdb\), and the service account
-- would need full control of it. In the container, xp_create_subdir creates the folder as
-- the mssql user, which runs SQL Server.
USE master;
SET NOCOUNT ON;
GO
-- 1. Before: where tempdb is.
SELECT name, physical_name FROM sys.master_files WHERE database_id = DB_ID(N'tempdb')
ORDER BY file_id;
GO
-- 2. The new folder, then one ALTER DATABASE ... MODIFY FILE per file, generated from
--    sys.master_files rather than typed: tempdb has nine files here.
DECLARE @folder nvarchar(260) = N'/var/opt/mssql/tempdb/';
EXEC master.dbo.xp_create_subdir @folder;

DECLARE @sql nvarchar(max);
SELECT @sql = STRING_AGG(CONVERT(nvarchar(max),
           CONCAT(N'ALTER DATABASE tempdb MODIFY FILE (NAME = ', QUOTENAME(name),
                  N', FILENAME = N''', @folder,
                  RIGHT(physical_name, CHARINDEX(N'/', REVERSE(physical_name)) - 1),
                  N''');')), NCHAR(10)) WITHIN GROUP (ORDER BY file_id)
FROM sys.master_files
WHERE database_id = DB_ID(N'tempdb');
PRINT @sql;
EXEC (@sql);
GO
-- 3. Both catalog views already give the new paths: master_files, and tempdb's own
--    database_files. The files in use are still the old ones until the restart: the new
--    folder is empty, as ls shows in 02-throwaway-container.sh.
SELECT mf.name, mf.physical_name AS master_files, df.physical_name AS database_files
FROM sys.master_files AS mf
JOIN tempdb.sys.database_files AS df ON df.file_id = mf.file_id
WHERE mf.database_id = DB_ID(N'tempdb')
ORDER BY mf.file_id;
GO
