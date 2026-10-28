-- Module 10, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It gives the instance back as setup/install.sh left it, and takes a few seconds:
-- 1. Drops the jobs of the module with their history and schedules, then the category
--    Exports. Ola Hallengren's ten jobs stay.
-- 2. Drops the alerts, the operator and the user message 50100.
-- 3. Deletes all the messages and the log of Database Mail (on the lab, only the module's),
--    drops the profile and its two accounts, sets the global parameters back to their
--    values on the lab, and turns Database Mail XPs and show advanced options back off.
-- 4. Drops the database AgentDemo and its backup history, and deletes its backup file. The
--    empty folder stays (T-SQL does not delete folders):
--      docker exec sqladmcourse rmdir /var/opt/mssql/backup/module_10
-- What T-SQL does not undo: the Agent's mail profile written by 07-agent-profile.sh in
-- /var/opt/mssql/mssql.conf. Without its profile in msdb, it does nothing; to remove it:
--   docker exec sqladmcourse /opt/mssql/bin/mssql-conf unset sqlagent.databasemailprofile
-- then a restart, as in 07-agent-profile.sh. PachadataTraining is restored by the next
-- module's 00-setup.sql.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The jobs, then the category.
DECLARE @job sysname;
DECLARE jobs CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM dbo.sysjobs
    WHERE name IN (N'Nightly invoice export', N'Linux subsystems', N'Log space watch',
                   N'Failing test');
OPEN jobs;
FETCH jobs INTO @job;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_delete_job @job_name = @job, @delete_unused_schedule = 1;
    FETCH jobs INTO @job;
END;
CLOSE jobs;
DEALLOCATE jobs;
IF EXISTS (SELECT * FROM dbo.syscategories WHERE name = N'Exports' AND category_class = 1)
    EXEC dbo.sp_delete_category @class = N'JOB', @name = N'Exports';
GO
-- 2. The alerts, the operator, the message.
DECLARE @alert sysname;
WHILE EXISTS (SELECT * FROM dbo.sysalerts WHERE name LIKE N'PachaData - %')
BEGIN
    SELECT TOP (1) @alert = name FROM dbo.sysalerts WHERE name LIKE N'PachaData - %';
    EXEC dbo.sp_delete_alert @name = @alert;
END;
IF EXISTS (SELECT * FROM dbo.sysoperators WHERE name = N'DBA team')
    EXEC dbo.sp_delete_operator @name = N'DBA team';
IF EXISTS (SELECT * FROM sys.messages WHERE message_id = 50100)
    EXEC master.dbo.sp_dropmessage @msgnum = 50100, @lang = 'all';
GO
-- 3. Database Mail.
DECLARE @now datetime = DATEADD(day, 1, GETDATE());
EXEC dbo.sysmail_delete_mailitems_sp @sent_before = @now;
EXEC dbo.sysmail_delete_log_sp @logged_before = @now;
IF EXISTS (SELECT * FROM dbo.sysmail_profile WHERE name = N'PachadataMail')
    EXEC dbo.sysmail_delete_profile_sp @profile_name = N'PachadataMail';
IF EXISTS (SELECT * FROM dbo.sysmail_account WHERE name = N'Company relay')
    EXEC dbo.sysmail_delete_account_sp @account_name = N'Company relay';
IF EXISTS (SELECT * FROM dbo.sysmail_account WHERE name = N'Lab Mailpit')
    EXEC dbo.sysmail_delete_account_sp @account_name = N'Lab Mailpit';
EXEC dbo.sysmail_configure_sp @parameter_name = N'AccountRetryAttempts', @parameter_value = N'1';
EXEC dbo.sysmail_configure_sp @parameter_name = N'AccountRetryDelay', @parameter_value = N'60';
GO
USE master;
GO
-- Database Mail XPs is an advanced option: it is visible only with show advanced options.
EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
EXEC sp_configure 'Database Mail XPs', 0; RECONFIGURE;
EXEC sp_configure 'show advanced options', 0; RECONFIGURE;
GO
-- 4. AgentDemo.
IF DB_ID(N'AgentDemo') IS NOT NULL
BEGIN
    ALTER DATABASE AgentDemo SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE AgentDemo;
END;
EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'AgentDemo';
-- The folder exists only when 11-log-watch.sql ran: xp_delete_file fails on a missing folder.
DECLARE @folders TABLE (subdirectory nvarchar(400), depth int);
INSERT INTO @folders EXEC master.sys.xp_dirtree N'/var/opt/mssql/backup', 1;
IF EXISTS (SELECT * FROM @folders WHERE subdirectory = N'module_10')
    EXEC master.sys.xp_delete_file 0, N'/var/opt/mssql/backup/module_10', N'bak', N'2100-01-01', 0;
GO
-- What is left of the module: nothing.
SELECT (SELECT COUNT(*) FROM msdb.dbo.sysjobs) AS jobs,
       (SELECT COUNT(*) FROM msdb.dbo.sysoperators) AS operators,
       (SELECT COUNT(*) FROM msdb.dbo.sysalerts) AS alerts,
       (SELECT COUNT(*) FROM msdb.dbo.sysmail_profile) AS mail_profiles,
       (SELECT COUNT(*) FROM msdb.dbo.sysmail_account) AS mail_accounts,
       (SELECT CAST(value_in_use AS int) FROM sys.configurations
        WHERE name = N'Database Mail XPs') AS database_mail_xps;
GO
