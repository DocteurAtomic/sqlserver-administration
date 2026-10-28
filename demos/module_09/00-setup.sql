-- Module 9, setup. Runs on the lab, in one session, before the first clip of the module.
-- It takes about five seconds.
-- 1. Removes what an earlier run of the module may have left on the instance: the server
--    audit of clip 9.4, its two specifications and the logins of the clip. The audit
--    files stay on disk; 99-cleanup.sql says how to delete them.
-- 2. Restores PachadataTraining as delivered, at level 170.
-- 3. Builds what the base does not have: the sales territories. Contact.Company has no
--    sales representative, so a table Sales.CompanyAssignment gives each of the 2,000
--    companies to one of three representatives, by country:
--    Margaux has France, Lukas Germany, Switzerland and the Benelux, Sofia the rest. The
--    ten last companies, 1991 to 2000, are new and have no representative yet.
-- 4. Creates the users of the clips, without login: the three representatives in the role
--    SalesReps, their manager Helene in the role SalesManagers. EXECUTE AS USER lets us
--    see the database with their eyes.
USE master;
SET NOCOUNT ON;
GO
-- 1. Leftovers of an earlier run, the database specification first.
IF DB_ID(N'PachadataTraining') IS NOT NULL
    EXEC (N'USE PachadataTraining;
IF EXISTS (SELECT * FROM sys.database_audit_specifications WHERE name = N''TrainerRateAccess'')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION TrainerRateAccess WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION TrainerRateAccess;
END;');
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
IF SUSER_ID(N'PachadataAuditor') IS NOT NULL DROP LOGIN PachadataAuditor;
IF SUSER_ID(N'PachadataPayroll') IS NOT NULL DROP LOGIN PachadataPayroll;
GO
-- 2. The database as delivered.
EXEC master.dbo.reset_training @db = N'PachadataTraining';
GO
USE PachadataTraining;
GO
-- 3. The sales territories.
CREATE SCHEMA Sales AUTHORIZATION dbo;
GO
CREATE TABLE Sales.CompanyAssignment (
    CompanyId int NOT NULL
        CONSTRAINT PK_CompanyAssignment PRIMARY KEY
        CONSTRAINT FK_CompanyAssignment_Company REFERENCES Contact.Company (CompanyId),
    SalesRep sysname NOT NULL,
    AssignedOn date NOT NULL CONSTRAINT DF_CompanyAssignment_AssignedOn DEFAULT ('2026-01-05')
);
CREATE INDEX IX_CompanyAssignment_SalesRep ON Sales.CompanyAssignment (SalesRep);
INSERT INTO Sales.CompanyAssignment (CompanyId, SalesRep)
SELECT CompanyId,
       CASE WHEN CountryCode = 'FRA' THEN N'Margaux'
            WHEN CountryCode IN ('DEU', 'CHE', 'BEL', 'NLD', 'LUX') THEN N'Lukas'
            ELSE N'Sofia' END
FROM Contact.Company
WHERE CompanyId <= 1990;
GO
-- 4. The users and their rights.
CREATE USER Margaux WITHOUT LOGIN;
CREATE USER Lukas WITHOUT LOGIN;
CREATE USER Sofia WITHOUT LOGIN;
CREATE USER Helene WITHOUT LOGIN;
CREATE ROLE SalesReps AUTHORIZATION dbo;
CREATE ROLE SalesManagers AUTHORIZATION dbo;
ALTER ROLE SalesReps ADD MEMBER Margaux;
ALTER ROLE SalesReps ADD MEMBER Lukas;
ALTER ROLE SalesReps ADD MEMBER Sofia;
ALTER ROLE SalesManagers ADD MEMBER Helene;
GRANT SELECT, UPDATE ON Contact.Company TO SalesReps;
GRANT SELECT ON Contact.Contact TO SalesReps;
GRANT SELECT, INSERT, UPDATE ON Sales.CompanyAssignment TO SalesReps;
GRANT SELECT ON SCHEMA::Contact TO SalesManagers;
GRANT SELECT ON SCHEMA::Sales TO SalesManagers;
GO
SELECT COALESCE(a.SalesRep, N'(none)') AS sales_rep, COUNT(*) AS companies
FROM Contact.Company AS c
LEFT JOIN Sales.CompanyAssignment AS a ON a.CompanyId = c.CompanyId
GROUP BY a.SalesRep
ORDER BY a.SalesRep;
