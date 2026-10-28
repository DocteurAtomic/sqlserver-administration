-- Clip 14.4: a server DDL trigger that records the creation, the change and the drop of
-- every database of the instance. Played for the video on the throwaway container sqladm-14:
-- ci: skip (it creates a server trigger and a table in DBA, instance objects)
-- On your lab, run it in one go; 99-cleanup.sql drops the trigger and the table.
-- 1. The log, in the administration database DBA.
-- 2. The trigger, stored in master, run for everybody, sysadmin included. A failure of a
--    server trigger stops the statement it fires on: SET XACT_ABORT OFF and TRY ... CATCH
--    keep the CREATE DATABASE alive if the log cannot be written.
-- 3. A database created, changed, dropped; the log; the server triggers of the instance.
USE DBA;
SET NOCOUNT ON;
GO
-- 1. The log.
CREATE TABLE dbo.DatabaseChangeLog (
    LogId        int IDENTITY PRIMARY KEY,
    EventTime    datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    EventType    sysname       NOT NULL,
    LoginName    sysname       NOT NULL,
    DatabaseName sysname       NOT NULL,
    Command      nvarchar(max) NULL
);
GO
-- 2. The trigger.
USE master;
GO
CREATE TRIGGER DatabaseChanges
ON ALL SERVER
FOR CREATE_DATABASE, ALTER_DATABASE, DROP_DATABASE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @e xml = EVENTDATA();
    BEGIN TRY
        INSERT INTO DBA.dbo.DatabaseChangeLog (EventType, LoginName, DatabaseName, Command)
        VALUES (@e.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname'),
                @e.value('(/EVENT_INSTANCE/LoginName)[1]', 'sysname'),
                @e.value('(/EVENT_INSTANCE/DatabaseName)[1]', 'sysname'),
                @e.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)'));
    END TRY
    BEGIN CATCH
        -- The log must never stop the creation or the drop of a database.
    END CATCH;
END;
GO
-- 3. A database for a test, created, changed, dropped.
CREATE DATABASE Module14Scratch;
GO
ALTER DATABASE Module14Scratch SET RECOVERY SIMPLE;
GO
DROP DATABASE Module14Scratch;
GO
SELECT LogId, EventType, LoginName, DatabaseName, LEFT(Command, 50) AS command
FROM DBA.dbo.DatabaseChangeLog
ORDER BY LogId;
SELECT t.name, t.is_disabled, te.type_desc AS event_type
FROM sys.server_triggers AS t
JOIN sys.server_trigger_events AS te ON te.object_id = t.object_id
ORDER BY t.name, te.type_desc;
