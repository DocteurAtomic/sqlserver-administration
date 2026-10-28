-- Clip 10.4: delegating the Agent to the operations team, without sysadmin. Runs on the
-- lab, in one session, in about ten seconds, after 01-export-job.sql. It creates a login and
-- drops it at the end.
-- 1. A login for the operations team, a user in msdb, and the role SQLAgentReaderRole.
-- 2. The reader sees every job but cannot start the export, which belongs to sa.
-- 3. With SQLAgentOperatorRole, it can.
-- 4. The user and the login dropped.
-- Lab password: in production, it lives in a secret store, never in a script.
USE master;
SET NOCOUNT ON;
GO
-- 1. The login and its user.
CREATE LOGIN PachadataOps WITH PASSWORD = N'Ops-2026!lab', CHECK_POLICY = ON;
GO
USE msdb;
GO
CREATE USER PachadataOps FOR LOGIN PachadataOps;
ALTER ROLE SQLAgentReaderRole ADD MEMBER PachadataOps;
GO
-- 2. As the reader.
EXECUTE AS LOGIN = N'PachadataOps';
SELECT COUNT(*) AS jobs_seen FROM dbo.sysjobs_view;
BEGIN TRY
    EXEC dbo.sp_start_job @job_name = N'Nightly invoice export';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
REVERT;
GO
-- 3. As an operator.
ALTER ROLE SQLAgentOperatorRole ADD MEMBER PachadataOps;
GO
DECLARE @last int = (SELECT ISNULL(MAX(instance_id), 0) FROM dbo.sysjobhistory);
EXECUTE AS LOGIN = N'PachadataOps';
EXEC dbo.sp_start_job @job_name = N'Nightly invoice export';
REVERT;
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
SELECT TOP (1) CASE h.run_status WHEN 0 THEN 'failed' WHEN 1 THEN 'succeeded' END AS outcome,
       LEFT(h.message, 120) AS message
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Nightly invoice export' AND h.step_id = 0
ORDER BY h.instance_id DESC;
GO
-- 4. Cleanup.
DROP USER PachadataOps;
GO
USE master;
GO
DROP LOGIN PachadataOps;
GO
