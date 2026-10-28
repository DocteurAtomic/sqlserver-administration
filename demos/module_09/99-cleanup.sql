-- Module 9, cleanup. Runs on the lab, in one session, after the clips and the exercise.
-- It gives the instance back as setup/install.sh left it, and takes a second:
-- 1. Turns off and drops the database audit specification, the server audit
--    specification and the server audit of clip 9.4, in this order: each object is turned
--    off before it is dropped.
-- 2. Drops the logins PachadataPayroll and PachadataAuditor.
-- The audit files stay on disk: dropping an audit does not delete them. On the lab:
--   docker exec sqladmcourse rm -rf /var/opt/mssql/audit
-- The policy, the masks, the ledger tables and the users of the clips live in
-- PachadataTraining, which the next module's 00-setup.sql restores.
USE PachadataTraining;
SET NOCOUNT ON;
GO
IF EXISTS (SELECT * FROM sys.database_audit_specifications WHERE name = N'TrainerRateAccess')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION TrainerRateAccess WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION TrainerRateAccess;
END;
IF USER_ID(N'Payroll') IS NOT NULL DROP USER Payroll;
GO
USE master;
GO
IF EXISTS (SELECT * FROM sys.server_audit_specifications WHERE name = N'PachadataServerAudit')
BEGIN
    ALTER SERVER AUDIT SPECIFICATION PachadataServerAudit WITH (STATE = OFF);
    DROP SERVER AUDIT SPECIFICATION PachadataServerAudit;
END;
IF EXISTS (SELECT * FROM sys.server_audits WHERE name = N'PachadataAudit')
BEGIN
    ALTER SERVER AUDIT PachadataAudit WITH (STATE = OFF);
    DROP SERVER AUDIT PachadataAudit;
END;
IF SUSER_ID(N'PachadataPayroll') IS NOT NULL DROP LOGIN PachadataPayroll;
IF SUSER_ID(N'PachadataAuditor') IS NOT NULL DROP LOGIN PachadataAuditor;
GO
SELECT (SELECT COUNT(*) FROM sys.server_audits) AS server_audits,
       (SELECT COUNT(*) FROM sys.server_audit_specifications) AS server_specifications,
       (SELECT COUNT(*) FROM sys.server_principals
        WHERE name IN (N'PachadataPayroll', N'PachadataAuditor')) AS logins;
GO
