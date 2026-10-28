-- Clip 10.4: the watch that replaces the alerts on Linux, as an Agent job. Runs on the lab,
-- in one session, in about a minute, after 09-alerts.sql.
-- ci: skip (it needs Database Mail and the test SMTP server)
-- 1. A small database, AgentDemo, in full recovery, whose 16 MB log cannot grow, backed up
--    once so that its log is no longer truncated at each checkpoint.
-- 2. The job Log space watch, every five minutes: it reads the counter Percent Log Used of
--    each database and the errors of severity 17 and above in the error log since its last
--    run, and mails the DBA team when it finds something.
-- 3. The log of AgentDemo filled to 85 % in a transaction, and an error of severity 17
--    written to the error log.
-- 4. The job started by hand, and the message it sent.
-- 99-cleanup.sql drops the job, the database and its backup file.
USE master;
SET NOCOUNT ON;
GO
-- 1. The database.
EXEC master.dbo.xp_create_subdir N'/var/opt/mssql/backup/module_10';
IF DB_ID(N'AgentDemo') IS NOT NULL
BEGIN
    ALTER DATABASE AgentDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE AgentDemo;
END;
CREATE DATABASE AgentDemo
    ON (NAME = AgentDemo, FILENAME = N'/var/opt/mssql/data/AgentDemo.mdf', SIZE = 64MB)
    LOG ON (NAME = AgentDemo_log, FILENAME = N'/var/opt/mssql/data/AgentDemo_log.ldf',
            SIZE = 16MB, FILEGROWTH = 0);
ALTER DATABASE AgentDemo SET RECOVERY FULL;
BACKUP DATABASE AgentDemo TO DISK = N'/var/opt/mssql/backup/module_10/AgentDemo.bak'
    WITH INIT, FORMAT;
GO
USE AgentDemo;
GO
CREATE TABLE dbo.Filler (content char(8000) NOT NULL);
GO
-- 2. The watch job. The counter's object is named after the instance (SQLServer:Databases
--    here, MSSQL$<instance>:Databases on a named instance): LIKE covers both.
USE msdb;
GO
EXEC dbo.sp_add_job @job_name = N'Log space watch', @owner_login_name = N'sa',
     @description = N'Replaces the Agent alerts on Linux';
EXEC dbo.sp_add_jobstep @job_name = N'Log space watch', @step_name = N'Read and mail',
     @subsystem = N'TSQL', @database_name = N'master',
     @command = N'DECLARE @since datetime = DATEADD(minute, -5, GETDATE());
DECLARE @log TABLE (LogDate datetime, ProcessInfo nvarchar(64), Text nvarchar(max));
INSERT INTO @log EXEC master.sys.xp_readerrorlog 0, 1, N''Severity: '', NULL, @since, NULL;
DECLARE @body nvarchar(max) = CONCAT_WS(CHAR(10),
    (SELECT STRING_AGG(CONCAT(N''Log of '', RTRIM(instance_name), N'': '', cntr_value, N'' % used''), CHAR(10))
     FROM sys.dm_os_performance_counters
     WHERE object_name LIKE N''%:Databases%'' AND counter_name = N''Percent Log Used''
       AND instance_name NOT IN (N''_Total'', N''mssqlsystemresource'') AND cntr_value > 70),
    (SELECT STRING_AGG(CONCAT(CONVERT(char(19), LogDate, 120), N'' '', Text), CHAR(10))
     FROM @log
     WHERE TRY_CAST(SUBSTRING(Text, CHARINDEX(N''Severity: '', Text) + 10, 2) AS int) >= 17));
IF @body <> N''''
    EXEC msdb.dbo.sp_notify_operator @profile_name = N''PachadataMail'',
         @name = N''DBA team'', @subject = N''Instance watch: something to look at'',
         @body = @body;';
EXEC dbo.sp_add_jobschedule @job_name = N'Log space watch', @name = N'Every 5 minutes',
     @freq_type = 4, @freq_interval = 1,
     @freq_subday_type = 4, @freq_subday_interval = 5;
EXEC dbo.sp_add_jobserver @job_name = N'Log space watch';
GO
-- 3. The log filled in an open transaction, then committed.
USE AgentDemo;
GO
DECLARE @rows int = 0;
BEGIN TRANSACTION;
WHILE (SELECT cntr_value FROM sys.dm_os_performance_counters
       WHERE object_name LIKE N'%:Databases%' AND counter_name = N'Percent Log Used'
         AND instance_name = N'AgentDemo') < 85
BEGIN
    INSERT INTO dbo.Filler (content) VALUES ('filler');
    SET @rows += 1;
END;
COMMIT;
SELECT @rows AS rows_inserted,
       (SELECT cntr_value FROM sys.dm_os_performance_counters
        WHERE object_name LIKE N'%:Databases%' AND counter_name = N'Percent Log Used'
          AND instance_name = N'AgentDemo') AS percent_log_used_after_commit;
GO
-- An error of severity 17, written to the error log.
BEGIN TRY
    RAISERROR (N'PachaData watch test: insufficient resources.', 17, 1) WITH LOG;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS raised, ERROR_SEVERITY() AS severity;
END CATCH;
GO
-- 4. The watch, started by hand instead of waiting up to five minutes.
USE msdb;
GO
DECLARE @last int = (SELECT ISNULL(MAX(mailitem_id), 0) FROM dbo.sysmail_allitems);
EXEC dbo.sp_start_job @job_name = N'Log space watch';
DECLARE @tries int = 0;
WHILE NOT EXISTS (SELECT * FROM dbo.sysmail_allitems
                  WHERE mailitem_id > @last AND sent_status IN ('sent', 'failed'))
      AND @tries < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
SELECT mailitem_id, recipients, subject, sent_status, body
FROM dbo.sysmail_allitems
WHERE mailitem_id > @last;
GO
