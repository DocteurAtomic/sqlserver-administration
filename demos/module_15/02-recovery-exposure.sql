-- Clip 15.2: what a failure of this server would cost today. Runs on the lab, in one session,
-- after 00-setup.sql. Reads the instance and changes nothing.
USE master;
SET NOCOUNT ON;
GO
-- 1. For each user database: recovery model, last full and last log backup taken on this
--    server, and how many minutes of changes a loss of the server would take with it.
SELECT d.name,
       d.recovery_model_desc,
       MAX(IIF(b.type = 'D', b.backup_finish_date, NULL)) AS last_full,
       MAX(IIF(b.type = 'L', b.backup_finish_date, NULL)) AS last_log,
       DATEDIFF(minute, MAX(b.backup_finish_date), SYSDATETIME()) AS minutes_exposed
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b
       ON b.database_name = d.name AND b.server_name = @@SERVERNAME
WHERE d.database_id > 4
GROUP BY d.name, d.recovery_model_desc
ORDER BY d.name;
GO
-- 2. The backup jobs, and whether the Agent will ever run them.
SELECT j.name AS job_name,
       j.enabled,
       COUNT(js.schedule_id) AS schedules
FROM msdb.dbo.sysjobs AS j
LEFT JOIN msdb.dbo.sysjobschedules AS js ON js.job_id = j.job_id
WHERE j.name LIKE N'DatabaseBackup%'
GROUP BY j.name, j.enabled
ORDER BY j.name;
GO
-- 3. The size to restore: the RTO starts with the time it takes to read this back.
SELECT d.name,
       CAST(SUM(mf.size) * 8 / 1024 AS int) AS size_mb
FROM sys.databases AS d
JOIN sys.master_files AS mf ON mf.database_id = d.database_id
WHERE d.database_id > 4
GROUP BY d.name
ORDER BY d.name;
GO
