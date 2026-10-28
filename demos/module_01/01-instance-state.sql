-- Clip 1.1: the instance of PachaData. Runs on the lab, in one session, after 00-setup.sql.
-- Reads the instance and changes nothing.
USE master;
SET NOCOUNT ON;
GO
-- 1. The instance we are connected to, and its databases.
SELECT @@SERVERNAME AS server_name,
       SERVERPROPERTY('MachineName') AS machine_name,
       SERVERPROPERTY('InstanceName') AS instance_name;

SELECT d.name, d.state_desc, d.recovery_model_desc, d.compatibility_level,
       CAST(SUM(mf.size) * 8 / 1024 AS int) AS size_mb
FROM sys.databases AS d
JOIN sys.master_files AS mf ON mf.database_id = d.database_id
GROUP BY d.name, d.database_id, d.state_desc, d.recovery_model_desc, d.compatibility_level
ORDER BY d.database_id;
GO
-- 2. What setup/install.sh added: the procedure that restores the course database, and Ola
--    Hallengren's jobs in msdb, none of them scheduled.
SELECT name FROM master.sys.procedures WHERE name = N'reset_training';

SELECT COUNT(*) AS jobs,
       (SELECT COUNT(*) FROM msdb.dbo.sysjobschedules) AS schedules
FROM msdb.dbo.sysjobs;
GO
-- 3. The starting point of the five guarantees of the DBA, one line each.
SELECT N'1. availability' AS guarantee, N'started at' AS measure,
       CONVERT(nvarchar(30), sqlserver_start_time, 120) AS value
FROM sys.dm_os_sys_info
UNION ALL
SELECT N'2. integrity', N'last good CHECKDB of PachadataTraining',
       CONVERT(nvarchar(30), DATABASEPROPERTYEX(N'PachadataTraining', 'LastGoodCheckDbTime'), 120)
UNION ALL
SELECT N'3. security', N'logins in sysadmin',
       CONVERT(nvarchar(30), COUNT(*))
FROM sys.server_principals
WHERE IS_SRVROLEMEMBER('sysadmin', name) = 1 AND type IN ('S', 'U', 'G')
UNION ALL
SELECT N'4. performance', N'max server memory (MB)',
       CONVERT(nvarchar(30), value_in_use)
FROM sys.configurations
WHERE name = N'max server memory (MB)'
UNION ALL
SELECT N'5. restore', N'backups taken on this server',
       CONVERT(nvarchar(30), COUNT(*))
FROM msdb.dbo.backupset
WHERE server_name = @@SERVERNAME;
GO
