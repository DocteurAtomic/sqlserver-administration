-- Clip 11.5: Ola Hallengren's integrity and index jobs, completed and scheduled. Played for
-- the video on the throwaway container sqladm-11, after 04b-ola-procedures.sql.
-- ci: skip (it changes and schedules Agent jobs, then waits for one of them)
-- On your lab, 99-cleanup.sql gives the jobs back as setup/install-ola.sh created them.
-- The request: every database checked each night, the indexes and statistics maintained once
-- a week, outside working hours, and a proof each morning.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The index job, completed: as installed, it calls IndexOptimize with its defaults, which
--    update no statistic.
EXEC dbo.sp_update_jobstep
    @job_name = N'IndexOptimize - USER_DATABASES', @step_id = 1,
    @command = N'EXECUTE dbo.IndexOptimize
@Databases = ''USER_DATABASES'',
@UpdateStatistics = ''ALL'',
@OnlyModifiedStatistics = ''Y'',
@LogToTable = ''Y''';
GO
-- 2. The schedules: integrity every night at 1:00 (freq_type 4), for the user databases and
--    the system databases, one schedule attached to both jobs; indexes and statistics every
--    Sunday at 2:00 (freq_type 8, weekly; freq_interval 1, Sunday).
EXEC dbo.sp_add_jobschedule
    @job_name = N'DatabaseIntegrityCheck - USER_DATABASES', @name = N'Integrity - every night at 1:00',
    @freq_type = 4, @freq_interval = 1, @active_start_time = 010000;
EXEC dbo.sp_attach_schedule
    @job_name = N'DatabaseIntegrityCheck - SYSTEM_DATABASES',
    @schedule_name = N'Integrity - every night at 1:00';
EXEC dbo.sp_add_jobschedule
    @job_name = N'IndexOptimize - USER_DATABASES', @name = N'Indexes - Sunday at 2:00',
    @freq_type = 8, @freq_interval = 1, @freq_recurrence_factor = 1, @active_start_time = 020000;
SELECT j.name AS job_name, sc.name AS schedule_name, sc.freq_type, sc.freq_interval,
       sc.active_start_time
FROM dbo.sysjobs AS j
JOIN dbo.sysjobschedules AS js ON js.job_id = j.job_id
JOIN dbo.sysschedules AS sc ON sc.schedule_id = js.schedule_id
ORDER BY j.name;
GO
-- 3. The two integrity jobs started by hand, then the history of the user databases' job once
--    it has finished.
EXEC dbo.sp_start_job @job_name = N'DatabaseIntegrityCheck - SYSTEM_DATABASES';
EXEC dbo.sp_start_job @job_name = N'DatabaseIntegrityCheck - USER_DATABASES';
WAITFOR DELAY '00:00:30';
SELECT h.step_id, h.step_name, h.run_status, h.run_duration, LEN(h.message) AS message_length,
       LEFT(h.message, 100) AS message
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'DatabaseIntegrityCheck - USER_DATABASES'
ORDER BY h.instance_id;
GO
-- 4. The output file of the step, in the folder of the error log, read without leaving SSMS.
--    The Agent writes it in Unicode (UTF-16): SINGLE_NCLOB, not SINGLE_CLOB (error 4806).
DECLARE @file nvarchar(400) = (
    SELECT TOP (1) full_filesystem_path
    FROM sys.dm_os_enumerate_filesystem(N'/var/opt/mssql/log', N'DatabaseIntegrityCheck*')
    ORDER BY last_write_time DESC);
SELECT @file AS output_file;
DECLARE @q nvarchar(max) = N'SELECT LEFT(BulkColumn, 600) AS output_start
    FROM OPENROWSET(BULK N''' + REPLACE(@file, N'''', N'''''') + N''', SINGLE_NCLOB) AS f;';
EXEC (@q);
GO
