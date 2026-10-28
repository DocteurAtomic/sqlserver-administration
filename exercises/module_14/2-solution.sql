-- Module 14 exercise: solution of parts 1 and 4, which run in one session. Read it after
-- searching. A few seconds. The errors that the developer receives are caught by
-- TRY ... CATCH and shown as a result, so that the script runs to its end. It writes only in PachadataTraining_Ex14 (part 4); part 1
-- only reads the logs. Parts 2 and 3 are in 5-solution-blocking.sql, and 6-cleanup.sql
-- removes what the exercise created.

-- ===== Part 1. The logs ================================================================
USE master;
SET NOCOUNT ON;
GO
-- 1. The restore of the copy, in the current error log: the restore itself, the options
--    that 1-start.sql changed, and the RCSI that it turned off.
EXEC sys.sp_readerrorlog 0, 1, N'PachadataTraining_Ex14', N'Setting database option';
EXEC sys.sp_readerrorlog 0, 1, N'Database was restored', N'PachadataTraining_Ex14';
GO
-- 2. The message of the release, over the last hour only.
DECLARE @start datetime = DATEADD(HOUR, -1, GETDATE()), @end datetime = GETDATE();
EXEC sys.xp_readerrorlog 0, 1, N'Exercise 14', NULL, @start, @end, N'desc';
GO
-- 3. The errors and the warnings of the Agent log: ErrorLevel 1 and 2.
DECLARE @agent TABLE (LogDate datetime, ErrorLevel int, Text nvarchar(4000));
INSERT INTO @agent EXEC sys.sp_readerrorlog 0, 2;
SELECT LogDate, ErrorLevel, LEFT(Text, 120) AS text
FROM @agent
WHERE ErrorLevel IN (1, 2)
ORDER BY LogDate;
GO
-- 4. The archives, and the startup of the instance: the cumulated DMVs start from there.
EXEC sys.xp_enumerrorlogs 1;
SELECT sqlserver_start_time FROM sys.dm_os_sys_info;
GO

-- ===== Part 4. The DDL trigger of the planning tool ====================================
USE PachadataTraining_Ex14;
GO
CREATE TABLE dbo.DdlLog (
    LogId     int IDENTITY PRIMARY KEY,
    EventTime datetime2(0)  NOT NULL DEFAULT SYSDATETIME(),
    EventType sysname       NOT NULL,
    UserName  sysname       NULL,
    ObjectName nvarchar(300) NULL,
    Command   nvarchar(max) NULL
);
GO
-- Version 1: written the obvious way.
CREATE TRIGGER PlanningDdl ON DATABASE FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @e xml = EVENTDATA();
    INSERT INTO dbo.DdlLog (EventType, UserName, ObjectName, Command)
    VALUES (@e.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname'),
            @e.value('(/EVENT_INSTANCE/UserName)[1]', 'sysname'),
            CONCAT(NULLIF(@e.value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname'), N'') + N'.',
                   @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname')),
            @e.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)'));
END;
GO
EXECUTE AS USER = N'PlanningDev';
BEGIN TRY
    CREATE TABLE Course.RoomRequest (RequestId int PRIMARY KEY, SessionId int NOT NULL);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
REVERT;
GO
-- Measured: error 229, "The INSERT permission was denied on the object 'DdlLog'", and the
-- table does not exist: the trigger runs in the transaction of the CREATE TABLE, with the
-- rights of the caller.
SELECT OBJECT_ID(N'Course.RoomRequest') AS v1_table;
GO
-- Version 2: TRY ... CATCH alone.
ALTER TRIGGER PlanningDdl ON DATABASE FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @e xml = EVENTDATA();
    BEGIN TRY
        INSERT INTO dbo.DdlLog (EventType, UserName, ObjectName, Command)
        VALUES (@e.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname'),
                @e.value('(/EVENT_INSTANCE/UserName)[1]', 'sysname'),
                CONCAT(NULLIF(@e.value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname'), N'') + N'.',
                       @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname')),
                @e.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)'));
    END TRY
    BEGIN CATCH
    END CATCH;
END;
GO
EXECUTE AS USER = N'PlanningDev';
BEGIN TRY
    CREATE TABLE Course.RoomRequest (RequestId int PRIMARY KEY, SessionId int NOT NULL);
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() AS error_number, ERROR_MESSAGE() AS error_message;
END CATCH;
REVERT;
GO
-- Measured: error 3616, "An error was raised during trigger execution. The batch has been
-- aborted and the user transaction, if any, has been rolled back." XACT_ABORT is ON in a
-- trigger: the 229 dooms the transaction, and the CATCH cannot save it.
SELECT OBJECT_ID(N'Course.RoomRequest') AS v2_table;
GO
-- Version 3: SET XACT_ABORT OFF as well.
ALTER TRIGGER PlanningDdl ON DATABASE FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @e xml = EVENTDATA();
    BEGIN TRY
        INSERT INTO dbo.DdlLog (EventType, UserName, ObjectName, Command)
        VALUES (@e.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname'),
                @e.value('(/EVENT_INSTANCE/UserName)[1]', 'sysname'),
                CONCAT(NULLIF(@e.value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname'), N'') + N'.',
                       @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname')),
                @e.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)'));
    END TRY
    BEGIN CATCH
    END CATCH;
END;
GO
EXECUTE AS USER = N'PlanningDev';
CREATE TABLE Course.RoomRequest (RequestId int PRIMARY KEY, SessionId int NOT NULL);
DROP TABLE Course.RoomRequest;
GO
REVERT;
GO
-- Measured: no error, the table was created and dropped, and the log has no line of the
-- developer: the change went through, its trace was lost without a word.
SELECT COUNT(*) AS v3_lines_of_planningdev FROM dbo.DdlLog WHERE UserName = N'PlanningDev';
GO
-- Version 4: EXECUTE AS N'dbo' as well.
ALTER TRIGGER PlanningDdl ON DATABASE WITH EXECUTE AS N'dbo' FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    DECLARE @e xml = EVENTDATA();
    BEGIN TRY
        INSERT INTO dbo.DdlLog (EventType, UserName, ObjectName, Command)
        VALUES (@e.value('(/EVENT_INSTANCE/EventType)[1]', 'sysname'),
                @e.value('(/EVENT_INSTANCE/UserName)[1]', 'sysname'),
                CONCAT(NULLIF(@e.value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname'), N'') + N'.',
                       @e.value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname')),
                @e.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]', 'nvarchar(max)'));
    END TRY
    BEGIN CATCH
    END CATCH;
END;
GO
EXECUTE AS USER = N'PlanningDev';
CREATE TABLE Course.RoomRequest (RequestId int PRIMARY KEY, SessionId int NOT NULL);
DROP TABLE Course.RoomRequest;
GO
REVERT;
GO
-- Measured: two lines of PlanningDev, CREATE_TABLE and DROP_TABLE. UserName is the
-- developer, not dbo: EVENTDATA() describes the event, not the execution context.
SELECT LogId, EventType, UserName, ObjectName
FROM dbo.DdlLog
ORDER BY LogId;
GO
-- The triggers of the database, and how many events the group covers.
SELECT t.name, t.is_disabled, COUNT(*) AS events
FROM sys.triggers AS t
JOIN sys.trigger_events AS te ON te.object_id = t.object_id
WHERE t.parent_class_desc = N'DATABASE'
GROUP BY t.name, t.is_disabled;
