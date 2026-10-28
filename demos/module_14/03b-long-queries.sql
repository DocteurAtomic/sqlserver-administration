-- Clip 14.3: an Extended Events session that records the slow statements of the database,
-- for a bounded time. Played for the video on the throwaway container sqladm-14:
-- ci: skip (it creates an event session, an instance object)
-- On your lab, run it in one go; 99-cleanup.sql drops the session. Its .xel files stay in
-- /var/opt/mssql/log: docker exec sqladmcourse sh -c 'rm /var/opt/mssql/log/LongQueries_*.xel'
-- 1. The session: the statements and the procedure calls of PachadataTraining that last
--    more than a quarter of a second, with the application, the user and the text. The
--    predicate is checked before the actions, so a statement that does not pass it costs
--    almost nothing. MAX_DURATION (SQL Server 2025) stops it by itself after eight hours.
-- 2. A query of the marketing report, three times, above the threshold, and a fast one.
-- 3. Stopping the session writes its buffers to the file; then the file is read in T-SQL.
USE master;
SET NOCOUNT ON;
GO
-- 1. The session, stopped at creation, then started.
CREATE EVENT SESSION LongQueries ON SERVER
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (sqlserver.client_app_name, sqlserver.client_hostname,
            sqlserver.username, sqlserver.sql_text)
    WHERE duration > 250000                          -- microseconds: a quarter of a second
      AND sqlserver.database_name = N'PachadataTraining'),
ADD EVENT sqlserver.rpc_completed (
    ACTION (sqlserver.client_app_name, sqlserver.client_hostname,
            sqlserver.username, sqlserver.sql_text)
    WHERE duration > 250000
      AND sqlserver.database_name = N'PachadataTraining')
ADD TARGET package0.event_file (
    SET filename = N'LongQueries.xel',               -- no path: the LOG folder
        max_file_size = 100,                         -- MB per file
        max_rollover_files = 5)
WITH (MAX_DISPATCH_LATENCY = 5 SECONDS,
      MAX_DURATION = 8 HOURS,
      STARTUP_STATE = OFF);
ALTER EVENT SESSION LongQueries ON SERVER STATE = START;
SELECT s.name, s.max_duration AS max_duration_s, t.target_name,
       CAST(t.target_data AS xml).value('(EventFileTarget/File/@name)[1]', 'nvarchar(260)') AS file_name
FROM sys.dm_xe_sessions AS x
JOIN sys.server_event_sessions AS s ON s.name = x.name
JOIN sys.dm_xe_session_targets AS t ON t.event_session_address = x.address
WHERE x.name = N'LongQueries';
GO
-- 2. The prospects by city, three times, and a fast count.
USE PachadataTraining;
GO
SELECT TOP (10) p.City, COUNT(*) AS prospects
FROM Contact.ProspectUS AS p
JOIN Contact.ProspectUS_N AS n ON n.Email = p.Email
GROUP BY p.City
ORDER BY prospects DESC
OPTION (MAXDOP 1);
GO 3
SELECT COUNT(*) AS sessions FROM Course.Session;
GO
-- 3. Stop, then read.
USE master;
GO
ALTER EVENT SESSION LongQueries ON SERVER STATE = STOP;
GO
WITH events AS (
    SELECT object_name AS event_name, timestamp_utc, CAST(event_data AS xml) AS x
    FROM sys.fn_xe_file_target_read_file(N'LongQueries*.xel', NULL, NULL, NULL)
)
SELECT event_name, timestamp_utc,
       x.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS duration_ms,
       x.value('(event/data[@name="cpu_time"]/value)[1]', 'bigint') / 1000 AS cpu_ms,
       x.value('(event/data[@name="logical_reads"]/value)[1]', 'bigint') AS logical_reads,
       x.value('(event/action[@name="client_app_name"]/value)[1]', 'nvarchar(128)') AS app,
       x.value('(event/action[@name="username"]/value)[1]', 'nvarchar(128)') AS username,
       LEFT(REPLACE(REPLACE(x.value('(event/data[@name="statement"]/value)[1]', 'nvarchar(max)'),
            CHAR(13), N''), CHAR(10), N' '), 60) AS statement
FROM events
ORDER BY timestamp_utc;
