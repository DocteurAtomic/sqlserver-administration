-- Clip 10.2: Database Mail, with the lab's test SMTP server. Runs on the lab, in one
-- session, in about half a minute, after the clip 10.1 scripts.
-- ci: skip (it needs the test SMTP server mail of compose.yaml, and changes the instance)
-- 1. The option Database Mail XPs, off by default.
-- 2. Two accounts: a relay that does not answer, then Mailpit, the lab's test SMTP server,
--    reached as mail:1025 on the network of compose.yaml. No address of this module is real:
--    the domain example is reserved for that.
-- 3. A profile that tries the two accounts in order, public and default.
-- 4. A test message, followed in the queue, the items and the log of Database Mail.
-- The messages are read in Mailpit: http://localhost:8025, or 05-mailpit.sh.
USE master;
SET NOCOUNT ON;
GO
-- 1. The option.
SELECT name, value_in_use FROM sys.configurations
WHERE name IN (N'show advanced options', N'Database Mail XPs');
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'Database Mail XPs', 1; RECONFIGURE;
GO
-- 2. The accounts. The first one is the company relay, down tonight.
USE msdb;
GO
EXEC dbo.sysmail_add_account_sp @account_name = N'Company relay',
     @email_address = N'sqlagent@pachadata.example', @display_name = N'SQL Server PachaData',
     @mailserver_name = N'relay.pachadata.example', @port = 25;
EXEC dbo.sysmail_add_account_sp @account_name = N'Lab Mailpit',
     @email_address = N'sqlagent@pachadata.example', @display_name = N'SQL Server PachaData',
     @mailserver_name = N'mail', @port = 1025;
-- 3. The profile: account 1 first, account 2 when account 1 fails.
EXEC dbo.sysmail_add_profile_sp @profile_name = N'PachadataMail',
     @description = N'Notifications of the DBA team';
EXEC dbo.sysmail_add_profileaccount_sp @profile_name = N'PachadataMail',
     @account_name = N'Company relay', @sequence_number = 1;
EXEC dbo.sysmail_add_profileaccount_sp @profile_name = N'PachadataMail',
     @account_name = N'Lab Mailpit', @sequence_number = 2;
-- Public: every user of msdb may use it. Default: used when no profile is named.
EXEC dbo.sysmail_add_principalprofile_sp @profile_name = N'PachadataMail',
     @principal_name = N'public', @is_default = 1;
GO
EXEC dbo.sysmail_help_profileaccount_sp @profile_name = N'PachadataMail';
EXEC dbo.sysmail_help_configure_sp @parameter_name = N'AccountRetryAttempts';
EXEC dbo.sysmail_help_configure_sp @parameter_name = N'AccountRetryDelay';
GO
-- 4. The test message. "Mail queued" only says it is in the queue.
EXEC dbo.sp_send_dbmail @profile_name = N'PachadataMail',
     @recipients = N'dba-team@pachadata.example',
     @subject = N'Database Mail test',
     @body = N'Sent by SQL Server through the profile PachadataMail.';
EXEC dbo.sysmail_help_status_sp;
WAITFOR DELAY '00:00:15';
SELECT mailitem_id, recipients, subject, sent_account_id, sent_status, send_request_date, sent_date
FROM dbo.sysmail_allitems
ORDER BY mailitem_id;
-- The log of Database Mail. A failure is a .NET trace: its first Message line gives the cause.
SELECT l.log_id, l.event_type, l.mailitem_id, l.account_id,
       CASE WHEN m.pos > 0
            THEN LEFT(SUBSTRING(l.description, m.pos, 200),
                      CHARINDEX(CHAR(13), SUBSTRING(l.description, m.pos, 200) + CHAR(13)) - 1)
            ELSE LEFT(l.description, 120) END AS cause
FROM dbo.sysmail_event_log AS l
CROSS APPLY (SELECT CHARINDEX(N'Message: ', l.description) AS pos) AS m
ORDER BY l.log_id;
GO
