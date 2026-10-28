-- Clip 10.3: an operator, and a job that notifies it when it fails. Runs on the lab, in one
-- session, in about twenty seconds, after 04-database-mail.sql.
-- ci: skip (it needs Database Mail and the test SMTP server)
-- 1. The operator: the mailing list of the DBA team, not a person.
-- 2. A job that fails on purpose and notifies the operator on failure.
-- 3. The job started: the Agent has no mail profile yet, the history says so, and no
--    message reaches the queue of Database Mail.
-- 07-agent-profile.sh gives the Agent its profile; the same job is started again there.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The operator. Pager and net send still exist in sp_add_operator, and are deprecated.
EXEC dbo.sp_add_operator @name = N'DBA team', @enabled = 1,
     @email_address = N'dba-team@pachadata.example';
GO
-- 2. The job. @notify_level_email: 1 on success, 2 on failure, 3 on completion.
EXEC dbo.sp_add_job @job_name = N'Failing test', @owner_login_name = N'sa',
     @notify_level_email = 2, @notify_email_operator_name = N'DBA team';
EXEC dbo.sp_add_jobstep @job_name = N'Failing test', @step_name = N'Divide by zero',
     @subsystem = N'TSQL', @command = N'SELECT 1 / 0;';
EXEC dbo.sp_add_jobserver @job_name = N'Failing test';
GO
-- 3. The run, and what the Agent did with the notification.
DECLARE @mails int = (SELECT COUNT(*) FROM dbo.sysmail_allitems);
EXEC dbo.sp_start_job @job_name = N'Failing test';
DECLARE @tries int = 0;
WHILE NOT EXISTS (SELECT * FROM dbo.sysjobhistory AS h
                  JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
                  WHERE j.name = N'Failing test' AND h.step_id = 0)
      AND @tries < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
WAITFOR DELAY '00:00:05';
SELECT h.step_id, CASE h.run_status WHEN 0 THEN 'failed' WHEN 1 THEN 'succeeded' END AS status,
       h.message
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Failing test' AND h.step_id = 0;
SELECT COUNT(*) - @mails AS new_messages_in_the_queue FROM dbo.sysmail_allitems;
GO
