-- Clip 10.3: the export mailed to the accounting team as a CSV file, and the DBA team
-- notified when it fails. Runs on the lab, in one session, in about twenty seconds, after
-- 07-agent-profile.sh.
-- ci: skip (it needs Database Mail, the test SMTP server and the Agent's mail profile)
-- 1. A step inserted between the copy and the failure step: it mails the table as a file
--    with sp_send_dbmail. The step that follows it is renumbered.
-- 2. Step 2 now goes on to step 3 when it succeeds; the job notifies the operator when it
--    fails.
-- 3. The job started; the message and its attachment, in msdb and in Mailpit.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The new step 3. The query runs in a session of its own, in the database named by
--    @execute_query_database. One column, already separated by semicolons, and no header
--    from Database Mail: its header would be followed by a line of dashes.
EXEC dbo.sp_add_jobstep @job_name = N'Nightly invoice export', @step_id = 3,
     @step_name = N'Mail the file to accounting', @subsystem = N'TSQL',
     @database_name = N'PachadataTraining',
     @command = N'DECLARE @day date, @n int, @subject nvarchar(255), @body nvarchar(max);
SELECT @day = MIN(InvoiceDate), @n = COUNT(*) FROM Export.DailyInvoice;
SET @subject = CONCAT(N''Invoices of '', @day);
SET @body = CONCAT(@n, N'' invoices and credit notes of '', @day, N'', attached as a CSV file.'');
EXEC msdb.dbo.sp_send_dbmail @profile_name = N''PachadataMail'',
     @recipients = N''accounting@pachadata.example'',
     @subject = @subject, @body = @body,
     @execute_query_database = N''PachadataTraining'',
     @query = N''SET NOCOUNT ON;
SELECT line FROM (
    SELECT 0 AS o, ''''InvoiceCode;InvoiceDate;CompanyId;NetAmount;GrossAmount;DocumentType'''' AS line
    UNION ALL
    SELECT 1, CONCAT_WS('''';'''', InvoiceCode, InvoiceDate, CompanyId, NetAmount, GrossAmount, DocumentType)
    FROM Export.DailyInvoice) AS t
ORDER BY o, line;'',
     @attach_query_result_as_file = 1,
     @query_attachment_filename = N''invoices.csv'',
     @query_result_header = 0,
     @query_result_no_padding = 1;',
     @on_success_action = 1, @on_fail_action = 4, @on_fail_step_id = 4;
GO
-- 2. Step 2 goes on to the mail; the job notifies the DBA team of a failure.
EXEC dbo.sp_update_jobstep @job_name = N'Nightly invoice export', @step_id = 2,
     @on_success_action = 3;
EXEC dbo.sp_update_job @job_name = N'Nightly invoice export',
     @notify_level_email = 2, @notify_email_operator_name = N'DBA team';
GO
SELECT s.step_id, s.step_name, s.on_success_action, s.on_fail_action, s.on_fail_step_id
FROM dbo.sysjobsteps AS s
JOIN dbo.sysjobs AS j ON j.job_id = s.job_id
WHERE j.name = N'Nightly invoice export'
ORDER BY s.step_id;
GO
-- 3. The run.
DECLARE @last int = (SELECT ISNULL(MAX(instance_id), 0) FROM dbo.sysjobhistory);
EXEC dbo.sp_start_job @job_name = N'Nightly invoice export';
DECLARE @tries int = 0;
WHILE NOT EXISTS (SELECT * FROM dbo.sysjobhistory AS h
                  JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
                  WHERE j.name = N'Nightly invoice export' AND h.step_id = 0
                    AND h.instance_id > @last)
      AND @tries < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
WAITFOR DELAY '00:00:10';
SELECT h.step_id, h.step_name,
       CASE h.run_status WHEN 0 THEN 'failed' WHEN 1 THEN 'succeeded' END AS status
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Nightly invoice export' AND h.instance_id > @last
ORDER BY h.instance_id;
SELECT TOP (1) i.mailitem_id, i.recipients, i.subject, i.sent_status, a.filename, a.filesize
FROM dbo.sysmail_allitems AS i
LEFT JOIN dbo.sysmail_attachments AS a ON a.mailitem_id = i.mailitem_id
ORDER BY i.mailitem_id DESC;
-- The file itself is read in Mailpit: it is written in UTF-16, which explains its size.
GO
