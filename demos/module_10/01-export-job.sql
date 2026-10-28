-- Clip 10.1: the nightly export asked for by the accountant, as an Agent job of three T-SQL
-- steps. Runs on the lab, in one session, in about ten seconds, after 00-setup.sql.
-- 1. A category for the exports, and the job, owned by sa.
-- 2. Three steps: prepare the table, copy the invoices of the day (one retry, one minute
--    later), report the failure. Step 3 is reached only when step 2 fails for good.
-- 3. A schedule, Monday to Friday at 6:00, attached to the job, and the target server.
-- 4. The job started by hand, and its history read in msdb.
-- The base stops on 2026-10-18: the job exports the last day that has invoices. In
-- production, the day would be yesterday: DATEADD(day, -1, CAST(SYSDATETIME() AS date)).
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The category and the job.
EXEC dbo.sp_add_category @class = N'JOB', @type = N'LOCAL', @name = N'Exports';
EXEC dbo.sp_add_job @job_name = N'Nightly invoice export',
     @description = N'Invoices of the day for the accounting team',
     @category_name = N'Exports', @owner_login_name = N'sa';
GO
-- 2. The steps. on_success_action and on_fail_action: 1 quit with success, 2 quit with
--    failure, 3 go to the next step, 4 go to the step @on_*_step_id.
EXEC dbo.sp_add_jobstep @job_name = N'Nightly invoice export', @step_id = 1,
     @step_name = N'Prepare the export table', @subsystem = N'TSQL',
     @database_name = N'PachadataTraining',
     @command = N'DROP TABLE IF EXISTS Export.DailyInvoice;
CREATE TABLE Export.DailyInvoice (
    InvoiceCode varchar(50) NOT NULL PRIMARY KEY,
    InvoiceDate date NOT NULL,
    CompanyId int NULL,
    NetAmount decimal(9,2) NOT NULL,
    GrossAmount decimal(9,2) NOT NULL,
    DocumentType char(1) NOT NULL);',
     @on_success_action = 3, @on_fail_action = 2;

EXEC dbo.sp_add_jobstep @job_name = N'Nightly invoice export', @step_id = 2,
     @step_name = N'Copy the invoices of the day', @subsystem = N'TSQL',
     @database_name = N'PachadataTraining',
     @command = N'DECLARE @day date = (SELECT MAX(InvoiceDate) FROM Enrollment.Invoice);
INSERT INTO Export.DailyInvoice (InvoiceCode, InvoiceDate, CompanyId, NetAmount, GrossAmount, DocumentType)
SELECT InvoiceCode, InvoiceDate, CompanyId, NetAmount, GrossAmount, DocumentType
FROM Enrollment.Invoice
WHERE InvoiceDate = @day;',
     @retry_attempts = 1, @retry_interval = 1,
     @on_success_action = 1,
     @on_fail_action = 4, @on_fail_step_id = 3;

EXEC dbo.sp_add_jobstep @job_name = N'Nightly invoice export', @step_id = 3,
     @step_name = N'Report the failure', @subsystem = N'TSQL', @database_name = N'master',
     @command = N'RAISERROR (N''Nightly invoice export: the copy failed.'', 16, 1) WITH LOG;',
     @on_success_action = 2, @on_fail_action = 2;
GO
-- 3. Monday to Friday: 2 + 4 + 8 + 16 + 32 = 62 (Sunday is 1, Saturday 64), at 6:00.
EXEC dbo.sp_add_schedule @schedule_name = N'Weekdays at 6:00',
     @freq_type = 8, @freq_interval = 62, @freq_recurrence_factor = 1,
     @active_start_time = 060000;
EXEC dbo.sp_attach_schedule @job_name = N'Nightly invoice export',
     @schedule_name = N'Weekdays at 6:00';
-- Without a target server, the job exists and never runs.
EXEC dbo.sp_add_jobserver @job_name = N'Nightly invoice export', @server_name = N'(local)';
GO
SELECT s.step_id, s.step_name, s.on_success_action, s.on_fail_action, s.on_fail_step_id,
       s.retry_attempts, s.retry_interval
FROM dbo.sysjobsteps AS s
JOIN dbo.sysjobs AS j ON j.job_id = s.job_id
WHERE j.name = N'Nightly invoice export'
ORDER BY s.step_id;
GO
-- 4. Started by hand. sp_start_job returns at once: the job runs in the background, so we
--    wait for the last line of its history, step_id 0, the outcome of the run.
EXEC dbo.sp_start_job @job_name = N'Nightly invoice export';
DECLARE @tries int = 0;
WHILE NOT EXISTS (SELECT * FROM dbo.sysjobhistory AS h
                  JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
                  WHERE j.name = N'Nightly invoice export' AND h.step_id = 0)
      AND @tries < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
SELECT COUNT(*) AS exported_invoices, MIN(InvoiceDate) AS invoice_day
FROM PachadataTraining.Export.DailyInvoice;

SELECT h.step_id, h.step_name,
       CASE h.run_status WHEN 0 THEN 'failed' WHEN 1 THEN 'succeeded' WHEN 2 THEN 'retry'
                         WHEN 3 THEN 'canceled' WHEN 4 THEN 'in progress' END AS status,
       msdb.dbo.agent_datetime(h.run_date, h.run_time) AS started,
       h.run_duration AS duration_hhmmss, LEFT(h.message, 90) AS message
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Nightly invoice export'
ORDER BY h.instance_id;

-- The next scheduled run.
SELECT j.name, a.next_scheduled_run_date
FROM dbo.sysjobactivity AS a
JOIN dbo.sysjobs AS j ON j.job_id = a.job_id
WHERE a.session_id = (SELECT MAX(session_id) FROM dbo.syssessions)
  AND j.name = N'Nightly invoice export';
GO
