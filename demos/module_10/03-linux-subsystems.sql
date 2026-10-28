-- Clip 10.1: what the Agent does not run on Linux. Runs on the lab, in one session, in
-- about ten seconds. It creates a job and a credential, and drops them at the end.
-- 1. The subsystems msdb knows.
-- 2. A job with a CmdExec step and a PowerShell step: both are created without error.
-- 3. The job started, and the history: the steps fail at run time.
-- 4. A proxy for CmdExec, refused: there is no Windows account on Linux.
-- 5. The job and the credential dropped.
USE msdb;
SET NOCOUNT ON;
GO
-- 1. The subsystems.
SELECT subsystem, subsystem_dll
FROM dbo.syssubsystems
ORDER BY subsystem_id;
GO
-- 2. The job. on_success_action 3: the PowerShell step runs even when CmdExec succeeds;
--    on_fail_action 3: and when it fails.
EXEC dbo.sp_add_job @job_name = N'Linux subsystems', @owner_login_name = N'sa';
EXEC dbo.sp_add_jobstep @job_name = N'Linux subsystems', @step_id = 1,
     @step_name = N'CmdExec', @subsystem = N'CmdExec',
     @command = N'ls /var/opt/mssql', @on_success_action = 3, @on_fail_action = 3;
EXEC dbo.sp_add_jobstep @job_name = N'Linux subsystems', @step_id = 2,
     @step_name = N'PowerShell', @subsystem = N'PowerShell',
     @command = N'Get-Date', @on_success_action = 1, @on_fail_action = 2;
EXEC dbo.sp_add_jobserver @job_name = N'Linux subsystems';
GO
-- 3. The run.
EXEC dbo.sp_start_job @job_name = N'Linux subsystems';
DECLARE @tries int = 0;
WHILE NOT EXISTS (SELECT * FROM dbo.sysjobhistory AS h
                  JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
                  WHERE j.name = N'Linux subsystems' AND h.step_id = 0)
      AND @tries < 60
BEGIN
    WAITFOR DELAY '00:00:01';
    SET @tries += 1;
END;
SELECT h.step_id, h.step_name,
       CASE h.run_status WHEN 0 THEN 'failed' WHEN 1 THEN 'succeeded' END AS status,
       LEFT(h.message, 200) AS message
FROM dbo.sysjobhistory AS h
JOIN dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'Linux subsystems'
ORDER BY h.instance_id;
GO
-- 4. A proxy needs a credential, which holds a Windows account and its password.
USE master;
GO
CREATE CREDENTIAL ExchangeAccount
    WITH IDENTITY = N'PACHADATA\svc_exchange', SECRET = N'Not-a-real-password-1';
GO
BEGIN TRY
    EXEC msdb.dbo.sp_add_proxy @proxy_name = N'ExchangeProxy',
         @credential_name = N'ExchangeAccount', @enabled = 1;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
GO
-- 5. Cleanup.
IF EXISTS (SELECT * FROM msdb.dbo.sysproxies WHERE name = N'ExchangeProxy')
    EXEC msdb.dbo.sp_delete_proxy @proxy_name = N'ExchangeProxy';
DROP CREDENTIAL ExchangeAccount;
EXEC msdb.dbo.sp_delete_job @job_name = N'Linux subsystems';
GO
