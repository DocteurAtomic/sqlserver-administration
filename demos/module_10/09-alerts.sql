-- Clip 10.4: the alerts every production instance should have, and what they do on Linux.
-- Runs on the lab, in one session, in about forty seconds.
-- 1. The operator of clip 10.3, created here when it is missing.
-- 2. Ten alerts: errors 823, 824, 825 (the I/O path), severities 19 to 25 (fatal errors),
--    each notifying the operator by mail, at most once every ten minutes.
-- 3. A test: a user message written to the error log, an alert on it, the message raised.
--    On Windows the alert fires within seconds; on Linux occurrence_count stays at 0.
-- 99-cleanup.sql drops the alerts, the operator and the message.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The operator.
IF NOT EXISTS (SELECT * FROM dbo.sysoperators WHERE name = N'DBA team')
    EXEC dbo.sp_add_operator @name = N'DBA team', @enabled = 1,
         @email_address = N'dba-team@pachadata.example';
GO
-- 2. The ten alerts. An alert is defined on a message number or on a severity, never both:
--    the other parameter is 0.
DECLARE @name sysname, @error int, @severity int;
DECLARE alerts CURSOR LOCAL FAST_FORWARD FOR
    SELECT name, error, severity
    FROM (VALUES (N'PachaData - Error 823', 823, 0), (N'PachaData - Error 824', 824, 0),
                 (N'PachaData - Error 825', 825, 0),
                 (N'PachaData - Severity 19', 0, 19), (N'PachaData - Severity 20', 0, 20),
                 (N'PachaData - Severity 21', 0, 21), (N'PachaData - Severity 22', 0, 22),
                 (N'PachaData - Severity 23', 0, 23), (N'PachaData - Severity 24', 0, 24),
                 (N'PachaData - Severity 25', 0, 25)) AS a (name, error, severity);
OPEN alerts;
FETCH alerts INTO @name, @error, @severity;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC dbo.sp_add_alert @name = @name, @message_id = @error, @severity = @severity,
         @delay_between_responses = 600, @include_event_description_in = 1;
    EXEC dbo.sp_add_notification @alert_name = @name,
         @operator_name = N'DBA team', @notification_method = 1;
    FETCH alerts INTO @name, @error, @severity;
END;
CLOSE alerts;
DEALLOCATE alerts;
GO
SELECT a.name, a.message_id, a.severity, a.delay_between_responses, o.name AS operator
FROM dbo.sysalerts AS a
JOIN dbo.sysnotifications AS n ON n.alert_id = a.id
JOIN dbo.sysoperators AS o ON o.id = n.operator_id
WHERE a.name LIKE N'PachaData - %'
ORDER BY a.name;
GO
-- 3. The test. The alert engine reads the events the engine logs: on Windows, the
--    application event log. A user message created WITH_LOG is always logged.
EXEC master.dbo.sp_addmessage @msgnum = 50100, @severity = 16,
     @msgtext = N'PachaData alert test.', @with_log = 'true', @replace = 'replace';
EXEC dbo.sp_add_alert @name = N'PachaData - Test message 50100', @message_id = 50100,
     @delay_between_responses = 0, @include_event_description_in = 1;
EXEC dbo.sp_add_notification @alert_name = N'PachaData - Test message 50100',
     @operator_name = N'DBA team', @notification_method = 1;
GO
BEGIN TRY
    RAISERROR (50100, 16, 1);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS raised;
END CATCH;
WAITFOR DELAY '00:00:30';
SELECT name, occurrence_count, last_occurrence_date, last_occurrence_time
FROM dbo.sysalerts
WHERE name = N'PachaData - Test message 50100';
EXEC master.sys.xp_readerrorlog 0, 1, N'50100';
GO
