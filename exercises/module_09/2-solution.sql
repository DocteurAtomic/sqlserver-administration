-- Module 9 exercise: solution. Runs on your lab, in one session, after 1-start.sql.
-- A few seconds. Part 1 builds a row-level security policy driven by SESSION_CONTEXT;
-- part 2 audits the portal's updates and the changes to the policy, reads the audit, then
-- drops the audit and PachadataTraining_Ex09. The audit files stay in /var/opt/mssql/data:
--   docker exec sqladmcourse sh -c 'rm /var/opt/mssql/data/Ex09Audit_*.sqlaudit'
-- Part 1 changes the session context of this session for good (read_only): run the
-- solution in a new session, and close it afterwards.
USE PachadataTraining_Ex09;
SET NOCOUNT ON;
GO
-------------------------------------------------------------------------------------------
-- Part 1. Row-level security for an application that connects with one account.
-------------------------------------------------------------------------------------------
-- 1a. The function compares the trainer of the row with the TrainerId that the portal
--     puts in the session context. It lets Planning and db_owner through, and nobody
--     else: TrainerPortal without a context sees nothing.
CREATE SCHEMA Security AUTHORIZATION dbo;
GO
CREATE FUNCTION Security.fn_TrainerAccess (@TrainerId AS int)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS access
    WHERE (USER_NAME() = N'TrainerPortal'
           AND @TrainerId = CAST(SESSION_CONTEXT(N'TrainerId') AS int))
       OR IS_MEMBER(N'Planning') = 1
       OR IS_MEMBER(N'db_owner') = 1;
GO
-- 1b. One policy, two tables. The block predicate AFTER UPDATE stops a trainer from giving
--     a session to a colleague.
CREATE SECURITY POLICY Security.TrainerPortalPolicy
    ADD FILTER PREDICATE Security.fn_TrainerAccess(TrainerId) ON Trainer.TrainerRate,
    ADD FILTER PREDICATE Security.fn_TrainerAccess(TrainerId) ON Course.Session,
    ADD BLOCK PREDICATE Security.fn_TrainerAccess(TrainerId) ON Course.Session AFTER UPDATE
    WITH (STATE = ON);
GO
-- 1c. Camille, of Planning, and dbo see everything: 904 rates, 19,300 sessions.
EXECUTE AS USER = N'Camille';
SELECT USER_NAME() AS reader, (SELECT COUNT(*) FROM Trainer.TrainerRate) AS rates,
       (SELECT COUNT(*) FROM Course.Session) AS sessions;
REVERT;
SELECT USER_NAME() AS reader, (SELECT COUNT(*) FROM Trainer.TrainerRate) AS rates,
       (SELECT COUNT(*) FROM Course.Session) AS sessions;
GO
-- 1d. The portal, without and then with a context. @read_only = 1: the key cannot change
--     until the connection closes, so a query injected in the portal cannot become another
--     trainer.
EXECUTE AS USER = N'TrainerPortal';
SELECT N'no context' AS context, (SELECT COUNT(*) FROM Trainer.TrainerRate) AS rates,
       (SELECT COUNT(*) FROM Course.Session) AS sessions;
EXEC sys.sp_set_session_context @key = N'TrainerId', @value = 1, @read_only = 1;
SELECT N'trainer 1' AS context, (SELECT COUNT(*) FROM Trainer.TrainerRate) AS rates,
       (SELECT COUNT(*) FROM Course.Session) AS sessions;
BEGIN TRY
    EXEC sys.sp_set_session_context @key = N'TrainerId', @value = 2;
END TRY
BEGIN CATCH
    SELECT N'switch to trainer 2' AS attempt, ERROR_NUMBER() AS error, ERROR_MESSAGE() AS message;
END CATCH;
GO
-- 1e. Still as TrainerPortal, for trainer 1. Session 17791 is his, 17726 belongs to
--     trainer 2.
UPDATE Course.Session SET Remarks = 'Projector needed' WHERE SessionId = 17791;
SELECT 17791 AS session_id, @@ROWCOUNT AS rows_updated;
UPDATE Course.Session SET Remarks = 'Projector needed' WHERE SessionId = 17726;
SELECT 17726 AS session_id, @@ROWCOUNT AS rows_updated;
BEGIN TRY
    UPDATE Course.Session SET TrainerId = 2 WHERE SessionId = 17791;
END TRY
BEGIN CATCH
    SELECT N'give session 17791 to trainer 2' AS attempt, ERROR_NUMBER() AS error,
           ERROR_MESSAGE() AS message;
END CATCH;
REVERT;
GO
-------------------------------------------------------------------------------------------
-- Part 2. An audit of the portal's updates and of the changes to the policy.
-------------------------------------------------------------------------------------------
-- 2a. The server audit, its server specification (changes to audits), its database
--     specification (UPDATE on Course.Session by everyone, and every change of a schema
--     object, the security policy included). The audit starts last.
USE master;
GO
CREATE SERVER AUDIT Ex09Audit
TO FILE (FILEPATH = N'/var/opt/mssql/data/', MAXSIZE = 10 MB, MAX_ROLLOVER_FILES = 2)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
CREATE SERVER AUDIT SPECIFICATION Ex09ServerAudit
FOR SERVER AUDIT Ex09Audit
    ADD (AUDIT_CHANGE_GROUP)
WITH (STATE = ON);
GO
USE PachadataTraining_Ex09;
GO
CREATE DATABASE AUDIT SPECIFICATION Ex09DatabaseAudit
FOR SERVER AUDIT Ex09Audit
    ADD (UPDATE ON OBJECT::Course.Session BY public),
    ADD (SCHEMA_OBJECT_CHANGE_GROUP)
WITH (STATE = ON);
GO
USE master;
GO
ALTER SERVER AUDIT Ex09Audit WITH (STATE = ON);
GO
SELECT name, status_desc FROM sys.dm_server_audit_status WHERE name = N'Ex09Audit';
GO
USE PachadataTraining_Ex09;
GO
-- 2b. Events. The portal updates a remark of trainer 1 (a new session: the old context
--     is still read-only, and it is trainer 1). Then a db_owner turns the policy off for
--     a minute, and back on.
EXECUTE AS USER = N'TrainerPortal';
UPDATE Course.Session SET Remarks = 'Room on the ground floor' WHERE SessionId = 17816;
REVERT;
ALTER SECURITY POLICY Security.TrainerPortalPolicy WITH (STATE = OFF);
ALTER SECURITY POLICY Security.TrainerPortalPolicy WITH (STATE = ON);
GO
-- 2c. The audit, read from master. The events reach the file after QUEUE_DELAY.
USE master;
GO
WAITFOR DELAY '00:00:02';
SELECT f.action_id, a.name AS action_name, f.succeeded,
       f.server_principal_name, f.database_principal_name, f.object_name,
       LEFT(f.statement, 70) AS statement
FROM sys.fn_get_audit_file(N'/var/opt/mssql/data/Ex09Audit_*.sqlaudit', DEFAULT, DEFAULT) AS f
JOIN (SELECT DISTINCT action_id, name FROM sys.dm_audit_actions) AS a
  ON a.action_id = f.action_id
ORDER BY f.event_time, f.sequence_number;
GO
-------------------------------------------------------------------------------------------
-- Part 3. The cleanup: the database specification, the server specification, the audit,
-- each turned off before it is dropped, then the database.
-------------------------------------------------------------------------------------------
USE PachadataTraining_Ex09;
GO
ALTER DATABASE AUDIT SPECIFICATION Ex09DatabaseAudit WITH (STATE = OFF);
DROP DATABASE AUDIT SPECIFICATION Ex09DatabaseAudit;
GO
USE master;
GO
ALTER SERVER AUDIT SPECIFICATION Ex09ServerAudit WITH (STATE = OFF);
DROP SERVER AUDIT SPECIFICATION Ex09ServerAudit;
ALTER SERVER AUDIT Ex09Audit WITH (STATE = OFF);
DROP SERVER AUDIT Ex09Audit;
GO
ALTER DATABASE PachadataTraining_Ex09 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE PachadataTraining_Ex09;
GO
SELECT (SELECT COUNT(*) FROM sys.server_audits WHERE name = N'Ex09Audit') AS audits,
       (SELECT COUNT(*) FROM sys.server_audit_specifications WHERE name = N'Ex09ServerAudit')
           AS server_specifications,
       (SELECT COUNT(*) FROM sys.databases WHERE name = N'PachadataTraining_Ex09') AS databases;
GO
