-- ci: skip
-- Clip 3.3: after the restart, check where tempdb is. Runs on the throwaway container, after
-- 03a-move-tempdb.sql and the restart of 02-throwaway-container.sh.
USE master;
SET NOCOUNT ON;
GO
-- The two views agree, and tempdb was created again at this start.
SELECT mf.name, mf.physical_name AS master_files, df.physical_name AS database_files
FROM sys.master_files AS mf
JOIN tempdb.sys.database_files AS df ON df.file_id = mf.file_id
WHERE mf.database_id = DB_ID(N'tempdb')
ORDER BY mf.file_id;

SELECT d.create_date AS tempdb_created, i.sqlserver_start_time
FROM sys.databases AS d
CROSS JOIN sys.dm_os_sys_info AS i
WHERE d.name = N'tempdb';
GO
-- model survived the restart, and WebShop with it: nothing of 02b-model-template.sql was lost.
SELECT name, recovery_model_desc FROM sys.databases WHERE name IN (N'model', N'WebShop');
GO
