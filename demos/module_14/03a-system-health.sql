-- Clip 14.3: what the session system_health kept, without anybody asking. Runs on the lab,
-- in one session, after the clip 14.2 (without it, there is no lock wait to find, which
-- is not an error). It only reads.
-- 1. The session and its targets: it runs on every instance, from startup. Its events reach
--    the file at most MAX_DISPATCH_LATENCY after they happen: 120 seconds, measured. A
--    lock wait that has just ended may not be in the file yet: read again two minutes
--    later.
-- 2. Its files, by type of event. A file name without a path is searched in the LOG folder;
--    the * takes the whole series.
-- 3. The lock waits of more than 30 seconds (wait_info), the errors of severity 20 and more,
--    the deadlocks: the most recent first.
USE master;
SET NOCOUNT ON;
GO
-- 1. The session, its state, and the size of its file target.
SELECT s.name, s.startup_state, s.max_dispatch_latency AS max_dispatch_latency_ms,
       CAST(f.name AS sysname) AS field, CAST(f.value AS sysname) AS value
FROM sys.server_event_sessions AS s
JOIN sys.server_event_session_fields AS f ON f.event_session_id = s.event_session_id
WHERE s.name = N'system_health' AND f.name IN (N'max_file_size', N'max_rollover_files');
GO
-- 2. What the files hold.
SELECT object_name AS event_name, COUNT(*) AS events,
       MIN(timestamp_utc) AS first_utc, MAX(timestamp_utc) AS last_utc
FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
GROUP BY object_name
ORDER BY events DESC;
GO
-- 3. The lock waits, the serious errors and the deadlocks.
SELECT TOP (10) timestamp_utc, object_name AS event_name,
       x.value('(event/data[@name="wait_type"]/text)[1]', 'nvarchar(60)') AS wait_type,
       x.value('(event/data[@name="duration"]/value)[1]', 'bigint') AS duration_ms,
       x.value('(event/action[@name="session_id"]/value)[1]', 'int') AS session_id,
       LEFT(x.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)'), 80) AS sql_text,
       x.value('(event/data[@name="error_number"]/value)[1]', 'int') AS error_number
FROM sys.fn_xe_file_target_read_file(N'system_health*.xel', NULL, NULL, NULL)
CROSS APPLY (SELECT CAST(event_data AS xml)) AS e(x)
WHERE object_name IN (N'wait_info', N'error_reported', N'xml_deadlock_report')
ORDER BY timestamp_utc DESC;
