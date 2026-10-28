-- Module 10 exercise: solution. Runs on your lab, in one session, after 1-start.sql. It lasts
-- about a minute and a half: it waits for the retry of a step.
-- It creates on the instance a Database Mail profile and its account, an operator and two
-- jobs, and drops them at the end, with the copy PachadataTraining_Ex10. Database Mail XPs
-- goes back to 0 when no other mail profile is left on the instance.
-- The messages go to Mailpit, the test SMTP server of the lab (http://localhost:8025). On an
-- instance that cannot reach it, the script runs the same and the messages end as failed.

-- Part 1. Database Mail: a profile of its own, and a test message.
USE master;
SET NOCOUNT ON;
GO
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'Database Mail XPs', 1; RECONFIGURE;
GO
USE msdb;
GO
EXEC dbo.sysmail_add_account_sp @account_name = N'Ex10 Mailpit',
     @email_address = N'planning-jobs@pachadata.example', @display_name = N'Planning jobs',
     @mailserver_name = N'mail', @port = 1025;
EXEC dbo.sysmail_add_profile_sp @profile_name = N'Ex10 planning';
EXEC dbo.sysmail_add_profileaccount_sp @profile_name = N'Ex10 planning',
     @account_name = N'Ex10 Mailpit', @sequence_number = 1;
-- Public but not default: a job names it, nothing else uses it by chance.
EXEC dbo.sysmail_add_principalprofile_sp @profile_name = N'Ex10 planning',
     @principal_name = N'public', @is_default = 0;
DECLARE @id int;
EXEC dbo.sp_send_dbmail @profile_name = N'Ex10 planning',
     @recipients = N'dba-team@pachadata.example', @subject = N'Ex10 test',
     @body = N'Test of the profile Ex10 planning.', @mailitem_id = @id OUTPUT;
WAITFOR DELAY '00:00:10';
SELECT mailitem_id, subject, sent_status FROM dbo.sysmail_allitems WHERE mailitem_id = @id;
GO
-- Part 2. The operator.
EXEC dbo.sp_add_operator @name = N'Ex10 DBA team', @enabled = 1,
     @email_address = N'dba-team@pachadata.example';
GO
-- Part 3. The weekly job: four steps, Monday at 7:00.
EXEC dbo.sp_add_category @class = N'JOB', @type = N'LOCAL', @name = N'Ex10 planning';
EXEC dbo.sp_add_job @job_name = N'Ex10 weekly sessions', @owner_login_name = N'sa',
     @category_name = N'Ex10 planning',
     @description = N'Sessions of next week, mailed to the planning team on Monday';
-- Step 1: the table. Success: next step (3). Failure: quit with failure (2).
EXEC dbo.sp_add_jobstep @job_name = N'Ex10 weekly sessions', @step_id = 1,
     @step_name = N'Prepare the table', @subsystem = N'TSQL',
     @database_name = N'PachadataTraining_Ex10',
     @command = N'DROP TABLE IF EXISTS Planning.NextWeekSession;
CREATE TABLE Planning.NextWeekSession (
    SessionId int NOT NULL PRIMARY KEY, StartDate date NOT NULL, CourseId int NOT NULL,
    LanguageCode char(2) NOT NULL, Duration tinyint NULL, TrainerId int NULL,
    TrainingRoomId int NULL);',
     @on_success_action = 3, @on_fail_action = 2;
-- Step 2: the sessions. One retry a minute later; then step 4 on failure.
EXEC dbo.sp_add_jobstep @job_name = N'Ex10 weekly sessions', @step_id = 2,
     @step_name = N'Copy the sessions', @subsystem = N'TSQL',
     @database_name = N'PachadataTraining_Ex10',
     @command = N'DECLARE @monday date = ''2026-10-19'';   -- in production: the coming Monday
INSERT INTO Planning.NextWeekSession
SELECT SessionId, StartDate, CourseId, LanguageCode, Duration, TrainerId, TrainingRoomId
FROM Course.Session
WHERE StartDate >= @monday AND StartDate < DATEADD(day, 7, @monday)
  AND StatusCode <> ''CANCELED'';',
     @retry_attempts = 1, @retry_interval = 1,
     @on_success_action = 3, @on_fail_action = 4, @on_fail_step_id = 4;
-- Step 3: the CSV file. Success: quit with success (1). Failure: step 4.
EXEC dbo.sp_add_jobstep @job_name = N'Ex10 weekly sessions', @step_id = 3,
     @step_name = N'Mail the list', @subsystem = N'TSQL',
     @database_name = N'PachadataTraining_Ex10',
     @command = N'EXEC msdb.dbo.sp_send_dbmail @profile_name = N''Ex10 planning'',
     @recipients = N''planning@pachadata.example'',
     @subject = N''Sessions of next week'',
     @body = N''The sessions of next week are attached.'',
     @execute_query_database = N''PachadataTraining_Ex10'',
     @query = N''SET NOCOUNT ON;
SELECT line FROM (
    SELECT 0 AS o, ''''SessionId;StartDate;CourseId;LanguageCode;Duration;TrainerId;TrainingRoomId'''' AS line
    UNION ALL
    SELECT 1, CONCAT_WS('''';'''', SessionId, StartDate, CourseId, LanguageCode, Duration, TrainerId, TrainingRoomId)
    FROM Planning.NextWeekSession) AS t
ORDER BY o, line;'',
     @attach_query_result_as_file = 1, @query_attachment_filename = N''sessions.csv'',
     @query_result_header = 0, @query_result_no_padding = 1;',
     @on_success_action = 1, @on_fail_action = 4, @on_fail_step_id = 4;
-- Step 4: reached only on failure. It warns the operator without the Agent's mail profile,
-- then fails, so that the job ends as failed.
EXEC dbo.sp_add_jobstep @job_name = N'Ex10 weekly sessions', @step_id = 4,
     @step_name = N'Warn the DBA team', @subsystem = N'TSQL', @database_name = N'msdb',
     @command = N'EXEC msdb.dbo.sp_notify_operator @profile_name = N''Ex10 planning'',
     @name = N''Ex10 DBA team'', @subject = N''Ex10 weekly sessions failed'',
     @body = N''The weekly list of sessions was not sent. See the job history.'';
RAISERROR (N''Ex10 weekly sessions: failed.'', 16, 1);',
     @on_success_action = 2, @on_fail_action = 2;
-- Monday is 2 in the weekly mask (Sunday 1, Saturday 64).
EXEC dbo.sp_add_schedule @schedule_name = N'Ex10 Monday at 7:00',
     @freq_type = 8, @freq_interval = 2, @freq_recurrence_factor = 1,
     @active_start_time = 070000;
EXEC dbo.sp_attach_schedule @job_name = N'Ex10 weekly sessions',
     @schedule_name = N'Ex10 Monday at 7:00';
EXEC dbo.sp_add_jobserver @job_name = N'Ex10 weekly sessions';
GO
-- Part 4. A run that succeeds, then a run that fails.
DECLARE @last int = (SELECT ISNULL(MAX(instance_id), 0) FROM dbo.sysjobhistory);
EXEC dbo.sp_start_job @job_name = N'Ex10 weekly sessions';
WHILE NOT EXISTS (SELECT * FROM dbo.sysjobhistory AS h JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
                  WHERE j.name = N'Ex10 weekly sessions' AND h.step_id = 0 AND h.instance_id > @last)
    WAITFOR DELAY '00:00:01';
SELECT COUNT(*) AS sessions_listed FROM PachadataTraining_Ex10.Planning.NextWeekSession;
GO
EXEC dbo.sp_update_jobstep @job_name = N'Ex10 weekly sessions', @step_id = 2,
     @command = N'INSERT INTO Planning.NextWeekSession (SessionId, StartDate, CourseId, LanguageCode)
SELECT SessionId, StartDate, CourseId, LanguageCode FROM Course.MissingSession;';
DECLARE @last int = (SELECT ISNULL(MAX(instance_id), 0) FROM dbo.sysjobhistory);
EXEC dbo.sp_start_job @job_name = N'Ex10 weekly sessions';
WHILE NOT EXISTS (SELECT * FROM dbo.sysjobhistory AS h JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
                  WHERE j.name = N'Ex10 weekly sessions' AND h.step_id = 0 AND h.instance_id > @last)
    WAITFOR DELAY '00:00:01';
SELECT h.step_id, h.step_name,
       CASE h.run_status WHEN 0 THEN 'failed' WHEN 1 THEN 'succeeded' WHEN 2 THEN 'retry' END AS status,
       h.retries_attempted, msdb.dbo.agent_datetime(h.run_date, h.run_time) AS started,
       h.sql_message_id
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Ex10 weekly sessions' AND h.instance_id > @last
ORDER BY h.instance_id;
GO
-- Part 5. The morning watch: the failed jobs of the last day, mailed to the operator.
EXEC dbo.sp_add_job @job_name = N'Ex10 failed jobs', @owner_login_name = N'sa',
     @category_name = N'Ex10 planning';
EXEC dbo.sp_add_jobstep @job_name = N'Ex10 failed jobs', @step_name = N'List and mail',
     @subsystem = N'TSQL', @database_name = N'msdb',
     @command = N'DECLARE @body nvarchar(max) =
    (SELECT STRING_AGG(CONCAT(CONVERT(char(19), msdb.dbo.agent_datetime(h.run_date, h.run_time), 120),
                              N'' '', j.name), CHAR(10))
     FROM msdb.dbo.sysjobhistory AS h
     JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
     WHERE h.step_id = 0 AND h.run_status = 0
       AND msdb.dbo.agent_datetime(h.run_date, h.run_time) > DATEADD(day, -1, GETDATE()));
IF @body IS NOT NULL
    EXEC msdb.dbo.sp_notify_operator @profile_name = N''Ex10 planning'',
         @name = N''Ex10 DBA team'', @subject = N''Failed jobs of the last 24 hours'', @body = @body;';
EXEC dbo.sp_add_jobschedule @job_name = N'Ex10 failed jobs', @name = N'Ex10 every day at 7:30',
     @freq_type = 4, @freq_interval = 1, @active_start_time = 073000;
EXEC dbo.sp_add_jobserver @job_name = N'Ex10 failed jobs';
GO
DECLARE @last int = (SELECT ISNULL(MAX(instance_id), 0) FROM dbo.sysjobhistory);
EXEC dbo.sp_start_job @job_name = N'Ex10 failed jobs';
WHILE NOT EXISTS (SELECT * FROM dbo.sysjobhistory AS h JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
                  WHERE j.name = N'Ex10 failed jobs' AND h.step_id = 0 AND h.instance_id > @last)
    WAITFOR DELAY '00:00:01';
WAITFOR DELAY '00:00:10';
-- Every message of the exercise, as Database Mail recorded it.
SELECT i.mailitem_id, i.recipients, i.subject, i.sent_status, a.filename
FROM dbo.sysmail_allitems AS i
JOIN dbo.sysmail_profile AS p ON p.profile_id = i.profile_id
LEFT JOIN dbo.sysmail_attachments AS a ON a.mailitem_id = i.mailitem_id
WHERE p.name = N'Ex10 planning'
ORDER BY i.mailitem_id;
GO
-- Part 6. Cleanup.
EXEC dbo.sp_delete_job @job_name = N'Ex10 weekly sessions', @delete_unused_schedule = 1;
EXEC dbo.sp_delete_job @job_name = N'Ex10 failed jobs', @delete_unused_schedule = 1;
EXEC dbo.sp_delete_category @class = N'JOB', @name = N'Ex10 planning';
EXEC dbo.sp_delete_operator @name = N'Ex10 DBA team';
EXEC dbo.sysmail_delete_profile_sp @profile_name = N'Ex10 planning';
EXEC dbo.sysmail_delete_account_sp @account_name = N'Ex10 Mailpit';
GO
USE master;
GO
IF NOT EXISTS (SELECT * FROM msdb.dbo.sysmail_profile)
BEGIN
    EXEC sp_configure 'Database Mail XPs', 0; RECONFIGURE;
    EXEC sp_configure 'show advanced options', 0; RECONFIGURE;
END;
ALTER DATABASE PachadataTraining_Ex10 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining_Ex10;
GO
SELECT (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name LIKE N'Ex10%') AS ex10_jobs,
       (SELECT COUNT(*) FROM msdb.dbo.sysmail_profile WHERE name = N'Ex10 planning') AS ex10_profiles,
       (SELECT CAST(value_in_use AS int) FROM sys.configurations
        WHERE name = N'Database Mail XPs') AS database_mail_xps;
GO
