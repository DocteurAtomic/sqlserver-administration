-- Clip 14.4: a database DDL trigger that records every change of structure of
-- PachadataTraining. Runs on the lab, in one session. It changes only the database, which
-- the next 00-setup.sql restores.
-- 1. The log table, and the developer of the marketing site, who may change the structure
--    (db_ddladmin) and do nothing else: a user without login, impersonated by
--    EXECUTE AS USER.
-- 2. A first trigger, written the obvious way. It runs inside the transaction of the
--    statement, with the rights of the caller: the developer cannot write in the log
--    (229), and his CREATE TABLE is rolled back with the trigger. The error is caught and
--    shown as a result, so that the script runs to its end.
-- 3. The trigger as it should be: EXECUTE AS N'dbo' for the rights, SET XACT_ABORT OFF and
--    TRY ... CATCH so that a failure of the log never stops the change. The developer
--    creates, changes and drops a table; the log keeps his name, since EVENTDATA()
--    describes the event, not the execution context.
USE PachadataTraining;
SET NOCOUNT ON;
GO
-- 1. The log, and the developer.
CREATE TABLE dbo.SchemaChangeLog (
    LogId     int IDENTITY PRIMARY KEY,
    EventTime datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    EventType sysname       NOT NULL,
    LoginName sysname       NOT NULL,
    UserName  sysname       NULL,
    ObjectName nvarchar(300) NULL,
    Command   nvarchar(max) NULL,
    EventData xml           NOT NULL
);
CREATE USER MarketingDev WITHOUT LOGIN;
ALTER ROLE db_ddladmin ADD MEMBER MarketingDev;
GO
-- 2. The obvious trigger.
CREATE TRIGGER SchemaChanges
ON DATABASE
FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @e xml = EVENTDATA();
    INSERT INTO dbo.SchemaChangeLog (EventType, LoginName, UserName, ObjectName, Command, EventData)
    VALUES (@e.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname'),
            @e.value('(/EVENT_INSTANCE/LoginName)[1]', 'sysname'),
            @e.value('(/EVENT_INSTANCE/UserName)[1]', 'sysname'),
            CONCAT(NULLIF(@e.value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname'), N'') + N'.',
                   @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname')),
            @e.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)'),
            @e);
END;
GO
EXECUTE AS USER = N'MarketingDev';
BEGIN TRY
    CREATE TABLE Marketing.LandingPage (Url varchar(400) NOT NULL, CachedAt datetime2(0) NOT NULL);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
REVERT;
GO
SELECT OBJECT_ID(N'Marketing.LandingPage') AS table_created;
-- 3. The trigger as it should be.
GO
ALTER TRIGGER SchemaChanges
ON DATABASE
WITH EXECUTE AS N'dbo'
FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;          -- ON by default in a trigger
    DECLARE @e xml = EVENTDATA();
    BEGIN TRY
        INSERT INTO dbo.SchemaChangeLog (EventType, LoginName, UserName, ObjectName, Command, EventData)
        VALUES (@e.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname'),
                @e.value('(/EVENT_INSTANCE/LoginName)[1]', 'sysname'),
                @e.value('(/EVENT_INSTANCE/UserName)[1]', 'sysname'),
                CONCAT(NULLIF(@e.value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname'), N'') + N'.',
                       @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname')),
                @e.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)'),
                @e);
    END TRY
    BEGIN CATCH
        -- The log must never stop a change of structure.
    END CATCH;
END;
GO
EXECUTE AS USER = N'MarketingDev';
CREATE TABLE Marketing.LandingPage (Url varchar(400) NOT NULL, CachedAt datetime2(0) NOT NULL);
ALTER TABLE Marketing.LandingPage ADD Hits int NOT NULL DEFAULT 0;
CREATE INDEX IX_LandingPage_CachedAt ON Marketing.LandingPage (CachedAt);
DROP TABLE Marketing.LandingPage;
GO
REVERT;
GO
-- LoginName of a user without login is a SID: UserName gives the name.
SELECT LogId, EventType, UserName, ObjectName,
       LEFT(REPLACE(REPLACE(Command, CHAR(13), N''), CHAR(10), N' '), 50) AS command
FROM dbo.SchemaChangeLog
ORDER BY LogId;
SELECT t.name, t.parent_class_desc, t.is_disabled, COUNT(*) AS events
FROM sys.triggers AS t
JOIN sys.trigger_events AS te ON te.object_id = t.object_id
WHERE t.parent_class_desc = N'DATABASE'
GROUP BY t.name, t.parent_class_desc, t.is_disabled;
