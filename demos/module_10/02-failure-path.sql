-- Clip 10.1: the failure path of the export. Runs on the lab, in one session, after
-- 01-export-job.sql, and lasts about a minute and a half: it waits for the retry.
-- ci: skip (it waits for the one-minute retry of step 2)
-- 1. Step 2 now reads a table that does not exist.
-- 2. The job started, and the history once step 3 has run.
-- 3. Step 2 given back its command.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. A wrong table name in step 2.
EXEC dbo.sp_update_jobstep @job_name = N'Nightly invoice export', @step_id = 2,
     @command = N'INSERT INTO Export.DailyInvoice (InvoiceCode, InvoiceDate, CompanyId, NetAmount, GrossAmount, DocumentType)
SELECT InvoiceCode, InvoiceDate, CompanyId, NetAmount, GrossAmount, DocumentType
FROM Enrollment.MissingInvoice;';
GO
-- 2. The run: step 2 fails, waits one minute, fails again, then step 3 runs.
DECLARE @last int = (SELECT ISNULL(MAX(instance_id), 0) FROM dbo.sysjobhistory);
EXEC dbo.sp_start_job @job_name = N'Nightly invoice export';
DECLARE @tries int = 0;
WHILE NOT EXISTS (SELECT * FROM dbo.sysjobhistory AS h
                  JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
                  WHERE j.name = N'Nightly invoice export' AND h.step_id = 0
                    AND h.instance_id > @last)
      AND @tries < 150
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
SELECT h.step_id, h.step_name,
       CASE h.run_status WHEN 0 THEN 'failed' WHEN 1 THEN 'succeeded' WHEN 2 THEN 'retry'
                         WHEN 3 THEN 'canceled' WHEN 4 THEN 'in progress' END AS status,
       h.retries_attempted AS retry,
       msdb.dbo.agent_datetime(h.run_date, h.run_time) AS started,
       h.sql_message_id, h.sql_severity
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Nightly invoice export' AND h.instance_id > @last
ORDER BY h.instance_id;
-- The cause, in the message of step 2.
SELECT TOP (1) LEFT(h.message, 200) AS step_2_message
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Nightly invoice export' AND h.step_id = 2
ORDER BY h.instance_id DESC;
GO
-- 3. Step 2 as 01-export-job.sql wrote it.
EXEC dbo.sp_update_jobstep @job_name = N'Nightly invoice export', @step_id = 2,
     @command = N'DECLARE @day date = (SELECT MAX(InvoiceDate) FROM Enrollment.Invoice);
INSERT INTO Export.DailyInvoice (InvoiceCode, InvoiceDate, CompanyId, NetAmount, GrossAmount, DocumentType)
SELECT InvoiceCode, InvoiceDate, CompanyId, NetAmount, GrossAmount, DocumentType
FROM Enrollment.Invoice
WHERE InvoiceDate = @day;';
GO
