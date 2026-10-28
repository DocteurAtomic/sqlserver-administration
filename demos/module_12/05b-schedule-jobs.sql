-- Clip 12.5: the strategy scheduled by the Agent. Played for the video on the throwaway
-- container sqladm-12, after 05a-databasebackup.sql.
-- ci: skip (it changes and schedules Agent jobs, then waits for one of them)
-- On your lab, 99-cleanup.sql gives the jobs back as setup/install-ola.sh created them.
-- The request: lose no more than fifteen minutes of orders. Full backup every night at 1:00,
-- log backup every 15 minutes, files kept seven days (168 hours), ZSTD compression.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The step of the two jobs, as setup/install-ola.sh created them.
SELECT j.name AS job_name, s.step_id, s.subsystem, s.database_name, s.command
FROM dbo.sysjobs AS j
JOIN dbo.sysjobsteps AS s ON s.job_id = j.job_id
WHERE j.name IN (N'DatabaseBackup - USER_DATABASES - FULL', N'DatabaseBackup - USER_DATABASES - LOG')
ORDER BY j.name;
GO
-- 2. The steps rewritten: the folder of the module, seven days, ZSTD.
EXEC dbo.sp_update_jobstep
    @job_name = N'DatabaseBackup - USER_DATABASES - FULL', @step_id = 1,
    @command = N'EXECUTE dbo.DatabaseBackup @Databases = ''USER_DATABASES'',
@Directory = N''/var/opt/mssql/backup/module_12/ola'', @BackupType = ''FULL'',
@Verify = ''Y'', @Checksum = ''Y'', @Compress = ''Y'', @CompressionAlgorithm = ''ZSTD'',
@CleanupTime = 168, @LogToTable = ''Y''';
EXEC dbo.sp_update_jobstep
    @job_name = N'DatabaseBackup - USER_DATABASES - LOG', @step_id = 1,
    @command = N'EXECUTE dbo.DatabaseBackup @Databases = ''USER_DATABASES'',
@Directory = N''/var/opt/mssql/backup/module_12/ola'', @BackupType = ''LOG'',
@Verify = ''Y'', @Checksum = ''Y'', @Compress = ''Y'', @CompressionAlgorithm = ''ZSTD'',
@CleanupTime = 168, @LogToTable = ''Y''';
GO
-- 3. The schedules: every day at 1:00 (freq_type 4), every 15 minutes all day long
--    (freq_subday_type 4, interval 15).
EXEC dbo.sp_add_jobschedule
    @job_name = N'DatabaseBackup - USER_DATABASES - FULL', @name = N'Every night at 1:00',
    @freq_type = 4, @freq_interval = 1, @active_start_time = 010000;
EXEC dbo.sp_add_jobschedule
    @job_name = N'DatabaseBackup - USER_DATABASES - LOG', @name = N'Every 15 minutes',
    @freq_type = 4, @freq_interval = 1,
    @freq_subday_type = 4, @freq_subday_interval = 15, @active_start_time = 000000;
SELECT j.name AS job_name, sc.name AS schedule_name, sc.freq_type,
       sc.freq_subday_type, sc.freq_subday_interval, sc.active_start_time
FROM dbo.sysjobs AS j
JOIN dbo.sysjobschedules AS js ON js.job_id = j.job_id
JOIN dbo.sysschedules AS sc ON sc.schedule_id = js.schedule_id
ORDER BY j.name;
GO
-- 4. The log job started by hand, then its history once it has finished.
EXEC dbo.sp_start_job @job_name = N'DatabaseBackup - USER_DATABASES - LOG';
WAITFOR DELAY '00:00:10';
SELECT TOP (2) j.name AS job_name, h.step_id, h.step_name, h.run_status, h.run_duration,
       LEFT(h.message, 120) AS message
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'DatabaseBackup - USER_DATABASES - LOG'
ORDER BY h.instance_id DESC;
GO
-- 5. The proof that the request is met: the database is in FULL, its last log backup is
--    less than 15 minutes old, and the log job runs every 15 minutes.
SELECT d.name, d.recovery_model_desc,
       MAX(b.backup_finish_date) AS last_log_backup,
       DATEDIFF(minute, MAX(b.backup_finish_date), GETDATE()) AS minutes_ago
FROM sys.databases AS d
LEFT JOIN dbo.backupset AS b
       ON b.database_name = d.name AND b.type = 'L' AND b.server_name = @@SERVERNAME
WHERE d.name = N'PachadataTraining'
GROUP BY d.name, d.recovery_model_desc;
GO
