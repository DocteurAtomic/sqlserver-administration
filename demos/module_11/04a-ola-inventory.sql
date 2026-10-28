-- Clip 11.4: what Ola Hallengren's Maintenance Solution installs. Runs on the lab, after
-- setup/install-ola.sh (for the video, on the throwaway container sqladm-11, right after the
-- installation). Reads only.
USE DBA;
SET NOCOUNT ON;
GO
-- 1. The objects of the solution in DBA, and the version written in each procedure.
SELECT o.name, o.type_desc,
       SUBSTRING(m.definition, CHARINDEX(N'--// Version: ', m.definition) + 14, 19) AS version
FROM sys.objects AS o
LEFT JOIN sys.sql_modules AS m ON m.object_id = o.object_id
WHERE o.is_ms_shipped = 0 AND o.type IN ('P', 'U')
ORDER BY o.type_desc, o.name;
GO
-- 2. The jobs created in msdb: category, owner, the type and database of their only step,
--    their number of schedules.
SELECT j.name AS job_name, c.name AS category, SUSER_SNAME(j.owner_sid) AS owner,
       s.subsystem, s.database_name,
       (SELECT COUNT(*) FROM msdb.dbo.sysjobschedules AS js WHERE js.job_id = j.job_id) AS schedules
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.syscategories AS c ON c.category_id = j.category_id
JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = j.job_id
WHERE c.name = N'Database Maintenance'
ORDER BY j.name;
GO
-- 3. The command of the integrity and index jobs, and the output file of their step.
SELECT j.name AS job_name, s.command, s.output_file_name
FROM msdb.dbo.sysjobs AS j
JOIN msdb.dbo.sysjobsteps AS s ON s.job_id = j.job_id
WHERE j.name IN (N'DatabaseIntegrityCheck - USER_DATABASES', N'IndexOptimize - USER_DATABASES');
GO
