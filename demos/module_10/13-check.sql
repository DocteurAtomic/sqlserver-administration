-- Clip 10.4: the accountant's request, checked. Runs on the lab, in one session, in a
-- second, after the scripts of the module.
-- 1. The jobs of the module: schedule, next run, last outcome, who is notified.
-- 2. The messages Database Mail sent to the accounting team and to the DBA team.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The jobs.
SELECT j.name AS job, c.name AS category, s.name AS schedule,
       a.next_scheduled_run_date AS next_run,
       CASE jsrv.last_run_outcome WHEN 0 THEN 'failed' WHEN 1 THEN 'succeeded'
                                  WHEN 5 THEN 'unknown' END AS last_outcome,
       o.name AS notifies_on_failure
FROM dbo.sysjobs AS j
JOIN dbo.syscategories AS c ON c.category_id = j.category_id
LEFT JOIN dbo.sysjobschedules AS js ON js.job_id = j.job_id
LEFT JOIN dbo.sysschedules AS s ON s.schedule_id = js.schedule_id
LEFT JOIN dbo.sysjobservers AS jsrv ON jsrv.job_id = j.job_id
LEFT JOIN dbo.sysjobactivity AS a ON a.job_id = j.job_id
                                 AND a.session_id = (SELECT MAX(session_id) FROM dbo.syssessions)
LEFT JOIN dbo.sysoperators AS o ON o.id = j.notify_email_operator_id
                                AND j.notify_level_email IN (2, 3)
WHERE j.name IN (N'Nightly invoice export', N'Log space watch')
ORDER BY j.name;
GO
-- 2. The messages.
SELECT recipients, subject, sent_status, sent_date
FROM dbo.sysmail_allitems
WHERE recipients IN (N'accounting@pachadata.example', N'dba-team@pachadata.example')
ORDER BY mailitem_id;
GO
