-- Clip 14.4: the proof that the instance is under watch, one line per item of the request.
-- Runs on the lab, in one session, at the end of the module. It only reads: on a lab where
-- the module was not played, every item answers "no", which is not an error.
-- The items: the error log keeps thirty archives; successful backups no longer flood it
-- (trace flag 3226); sp_WhoIsActive is in DBA; system_health runs; the session LongQueries
-- exists and is bounded in time; the Query Store of PachadataTraining writes; the changes of
-- structure of the database and of the instance are logged.
USE master;
SET NOCOUNT ON;
GO
DECLARE @flags TABLE (TraceFlag int, Status int, Global int, Session int);
INSERT INTO @flags EXEC (N'DBCC TRACESTATUS (3226) WITH NO_INFOMSGS;');
DECLARE @logs TABLE (Value nvarchar(100), Data int);
INSERT INTO @logs EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',
     N'Software\Microsoft\MSSQLServer\MSSQLServer', N'NumErrorLogs';
DECLARE @qs nvarchar(60);
IF DB_ID(N'PachadataTraining') IS NOT NULL
    EXEC sys.sp_executesql
         N'SELECT @s = actual_state_desc FROM PachadataTraining.sys.database_query_store_options;',
         N'@s nvarchar(60) OUTPUT', @s = @qs OUTPUT;
DECLARE @dbtrigger bit = 0;
IF DB_ID(N'PachadataTraining') IS NOT NULL
    EXEC sys.sp_executesql
         N'SELECT @t = COUNT(*) FROM PachadataTraining.sys.triggers
           WHERE name = N''SchemaChanges'' AND parent_class_desc = N''DATABASE'' AND is_disabled = 0;',
         N'@t bit OUTPUT', @t = @dbtrigger OUTPUT;

SELECT item, CASE WHEN ok = 1 THEN 'yes' ELSE 'no' END AS ok, detail
FROM (VALUES
    (1, N'Error log: 30 archives',
        CASE WHEN (SELECT Data FROM @logs) >= 30 THEN 1 ELSE 0 END,
        CONCAT(N'NumErrorLogs = ', COALESCE(CAST((SELECT Data FROM @logs) AS nvarchar(10)), N'default (6)'))),
    (2, N'Trace flag 3226, global',
        CASE WHEN EXISTS (SELECT * FROM @flags WHERE Global = 1) THEN 1 ELSE 0 END, NULL),
    (3, N'sp_WhoIsActive in DBA',
        CASE WHEN OBJECT_ID(N'DBA.dbo.sp_WhoIsActive') IS NOT NULL THEN 1 ELSE 0 END, NULL),
    (4, N'system_health running',
        CASE WHEN EXISTS (SELECT * FROM sys.dm_xe_sessions WHERE name = N'system_health') THEN 1 ELSE 0 END, NULL),
    (5, N'Session LongQueries, bounded',
        CASE WHEN EXISTS (SELECT * FROM sys.server_event_sessions
                          WHERE name = N'LongQueries' AND max_duration > 0) THEN 1 ELSE 0 END,
        (SELECT CONCAT(N'max_duration = ', max_duration, N' s')
         FROM sys.server_event_sessions WHERE name = N'LongQueries')),
    (6, N'Query Store of PachadataTraining',
        CASE WHEN @qs = N'READ_WRITE' THEN 1 ELSE 0 END, @qs),
    (7, N'Database DDL trigger SchemaChanges', @dbtrigger, NULL),
    (8, N'Server DDL trigger DatabaseChanges',
        CASE WHEN EXISTS (SELECT * FROM sys.server_triggers
                          WHERE name = N'DatabaseChanges' AND is_disabled = 0) THEN 1 ELSE 0 END, NULL)
) AS c (n, item, ok, detail)
ORDER BY n;
