-- Clip 14.1: read the error log and the Agent log. Runs on the lab, in one session, after
-- 01b-events.sh (without it, the searches return nothing, which is not an error).
-- It only reads.
-- 1. Where the error log is, and its files: 0 is the current one, 1 to 6 the archives.
-- 2. The failed connections: each one writes two lines, the error with its state, then the
--    reason with the client address. "Login failed" finds the second, "Error: 18456" the
--    first.
-- 3. The same search over the last hour, newest first, by xp_readerrorlog, which is not
--    documented: file, log type (1 engine, 2 Agent), two strings, start, end, order.
-- 4. The message written by RAISERROR ... WITH LOG.
-- 5. The Agent log: the line that says the job failed, without the cause.
-- 6. The job history in msdb: the cause, step by step.
USE master;
SET NOCOUNT ON;
GO
-- 1. The files of the error log, and those of the Agent log.
SELECT SERVERPROPERTY('ErrorLogFileName') AS error_log;
EXEC sys.xp_enumerrorlogs 1;
EXEC sys.xp_enumerrorlogs 2;   -- on Linux, measured: no row
GO
-- 2. The failed connections, in the current file.
EXEC sys.sp_readerrorlog 0, 1, N'Login failed';
EXEC sys.sp_readerrorlog 0, 1, N'Error: 18456';
GO
-- 3. The last hour only, newest first.
DECLARE @start datetime = DATEADD(HOUR, -1, GETDATE()), @end datetime = GETDATE();
EXEC sys.xp_readerrorlog 0, 1, N'Login failed', N'sa', @start, @end, N'desc';
GO
-- 4. The message of the DBA team.
EXEC sys.sp_readerrorlog 0, 1, N'Module 14';
GO
-- 5. The Agent log: ErrorLevel 1 is an error, 2 a warning, 3 an information.
EXEC sys.sp_readerrorlog 0, 2, N'Nightly export';
GO
-- 6. The failed jobs of the last 24 hours, step by step. Step 0 is the summary line of the
--    job; the other steps have the message of the step.
SELECT j.name AS job, h.step_id, h.step_name,
       msdb.dbo.agent_datetime(h.run_date, h.run_time) AS run_at,
       h.sql_message_id, h.sql_severity, LEFT(h.message, 160) AS message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE h.run_status = 0
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= DATEADD(HOUR, -24, GETDATE())
ORDER BY run_at DESC, h.step_id DESC;
