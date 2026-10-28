-- Clip 9.4: a server audit of the reads of the trainers' rates. Played for the video on
-- the throwaway container sqladm-09:
-- ci: skip (it creates a server audit and two logins, instance objects)
-- On your lab, run it in one go, then 04b-events.sh and 04c-read-audit.sql; 99-cleanup.sql
-- drops the audit, its specifications and the logins.
-- 1. The folder of the audit files, owned by the account mssql.
-- 2. The server audit: the target and its behavior. It is created stopped.
-- 3. The server audit specification: failed logins, changes of server role members.
-- 4. The database audit specification: SELECT and UPDATE on Trainer.TrainerRate, by anyone.
-- 5. The audit started, and its state.
-- 6. The logins of the clip: the payroll accountant, who may read the rates, and the
--    auditor, who may read the audit and nothing else (VIEW SERVER SECURITY AUDIT, 2022).
--    Lab passwords: in production, they live in a secret store, never in a script.
USE master;
SET NOCOUNT ON;
GO
-- 1. On Windows, a folder such as D:\Audit\, where the service account writes and the
--    other administrators only read. On the container, a folder under /var/opt/mssql.
EXEC master.sys.xp_create_subdir N'/var/opt/mssql/audit';
GO
-- 2. The server audit.
CREATE SERVER AUDIT PachadataAudit
TO FILE (
    FILEPATH = N'/var/opt/mssql/audit/',
    MAXSIZE = 100 MB,
    MAX_ROLLOVER_FILES = 10
)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
GO
-- 3. The server specification: one per audit.
CREATE SERVER AUDIT SPECIFICATION PachadataServerAudit
FOR SERVER AUDIT PachadataAudit
    ADD (FAILED_LOGIN_GROUP),
    ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP)
WITH (STATE = ON);
GO
-- 4. The database specification: one per database and per audit. BY public covers every
--    user, since every user is a member of public.
USE PachadataTraining;
GO
CREATE DATABASE AUDIT SPECIFICATION TrainerRateAccess
FOR SERVER AUDIT PachadataAudit
    ADD (SELECT, UPDATE ON OBJECT::Trainer.TrainerRate BY public)
WITH (STATE = ON);
GO
-- 5. The audit starts last.
USE master;
GO
ALTER SERVER AUDIT PachadataAudit WITH (STATE = ON);
GO
SELECT name, status_desc, audit_file_path FROM sys.dm_server_audit_status;
SELECT a.name AS audit_name, a.type_desc, a.on_failure_desc, a.queue_delay,
       f.log_file_path, f.max_file_size, f.max_rollover_files
FROM sys.server_audits AS a
JOIN sys.server_file_audits AS f ON f.audit_id = a.audit_id;
GO
-- 6. The two logins.
CREATE LOGIN PachadataPayroll
    WITH PASSWORD = N'Payroll-2026!lab', DEFAULT_DATABASE = PachadataTraining,
         CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
CREATE LOGIN PachadataAuditor
    WITH PASSWORD = N'Auditor-2026!lab', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
GRANT VIEW SERVER SECURITY AUDIT TO PachadataAuditor;
GO
USE PachadataTraining;
GO
CREATE USER Payroll FOR LOGIN PachadataPayroll;
GRANT SELECT ON Trainer.TrainerRate TO Payroll;
GRANT SELECT ON Trainer.Trainer TO Payroll;
GO
