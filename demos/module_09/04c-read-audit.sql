-- Clip 9.4: the audit read by the auditor. Played for the video on the throwaway container
-- sqladm-09, after 04b-events.sh:
-- ci: skip (it needs the audit and the logins of 04a-server-audit.sql)
-- On your lab, run it in one go.
-- 1. The auditor, a login without any other right, reads the audit files through
--    sys.fn_get_audit_file: VIEW SERVER SECURITY AUDIT is enough since SQL Server 2022.
-- 2. The answer to the request: who read the trainers' rates, and when (UTC).
-- 3. The action codes, translated by sys.dm_audit_actions.
-- 4. The proof that the auditor can read the audit but not the rates.
USE master;
SET NOCOUNT ON;
GO
-- The events reach the file after QUEUE_DELAY, one second.
WAITFOR DELAY '00:00:02';
GO
-- 1. Every event, read as the auditor.
EXECUTE AS LOGIN = N'PachadataAuditor';
SELECT action_id, succeeded, session_server_principal_name AS session_login,
       database_principal_name AS db_user, object_name,
       LEFT(statement, 60) AS statement
FROM sys.fn_get_audit_file(N'/var/opt/mssql/audit/PachadataAudit_*.sqlaudit', DEFAULT, DEFAULT)
ORDER BY event_time, sequence_number;
REVERT;
GO
-- 2. The request of the data protection officer: who read the rates.
EXECUTE AS LOGIN = N'PachadataAuditor';
SELECT CONVERT(varchar(19), event_time, 120) AS event_time_utc,
       session_server_principal_name AS session_login, database_principal_name AS db_user,
       succeeded, LEFT(statement, 60) AS statement
FROM sys.fn_get_audit_file(N'/var/opt/mssql/audit/PachadataAudit_*.sqlaudit', DEFAULT, DEFAULT)
WHERE action_id = 'SL' AND object_name = N'TrainerRate'
ORDER BY event_time;
REVERT;
GO
-- 3. The codes of the actions.
SELECT DISTINCT f.action_id, a.name AS action_name
FROM sys.fn_get_audit_file(N'/var/opt/mssql/audit/PachadataAudit_*.sqlaudit', DEFAULT, DEFAULT) AS f
JOIN sys.dm_audit_actions AS a ON a.action_id = f.action_id
ORDER BY f.action_id;
GO
-- 4. The auditor has no user in PachadataTraining: the rates stay out of reach.
EXECUTE AS LOGIN = N'PachadataAuditor';
BEGIN TRY
    SELECT TOP (1) DailyRate FROM PachadataTraining.Trainer.TrainerRate;
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
REVERT;
GO
